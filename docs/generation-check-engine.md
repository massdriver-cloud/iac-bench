# Generation scoring: root-module evaluation and the declarative check engine

How the mechanical layer of the generation domain works: the execution model,
the evidence rules, and the check vocabulary. Engine: `src/iacbench/checks.py`;
harness: `src/iacbench/generation.py`; per-fixture checks: each fixture's
`rubric.yaml`.

**The core principle:** the unit under evaluation is the module at its
defaults plus the shape of its interface — never the inputs the model chose
to feed it. What the model *variablizes* is a scoreable design decision; what
it *sets variables to* is not. A module that exposes a security attribute as
a knob is insecure-by-design even if every example sets it safely, so
security is judged on the static source, and behavior is judged at the
module's own defaults.

**Versioning:** every score records its fixture's rubric edition
(`rubric_sha`, a hash of `rubric.yaml` and `baseline.yaml`), and the report
aggregates only attempts scored under the current edition. A scoring change
creates a new edition; stored candidates re-score under it with
`iacbench rescore`. `scoring_policy`, `SCAFFOLD_CONTRACT_VERSION` and
`CHECK_DSL_VERSION` version the composite formula, the agent scaffold and the
check vocabulary.

## Execution model: root module + model-supplied tfvars

The module is planned **as a root module**, never wrapped as a submodule in a
synthetic root: per `good-opentofu.md`, terraliths are an antipattern and the
deliverable is a standalone root module, so wrapping it as a submodule would
test exactly the consumption pattern the doctrine rejects. The scaffold
contract requires the model to ship a **`minimal.tfvars` (or
`minimal.tfvars.json`)** supplying values for its required variables — tfvars
values are literals by definition, so instantiation never depends on
expressions the harness would have to evaluate.

Mechanics:

- The harness copies the module to a work dir, runs `tofu init` **once**, then
  executes every plan (defaults + full perturbation sweep) as repeated
  `tofu plan -var-file=<generated>.tfvars.json` runs in that dir.
- **Defaults plan:** the model's tfvars are parsed and **filtered to variables
  with no default** before planning. Without this filter, optional values in
  the tfvars would smuggle the model's choices into what is supposed to be
  out-of-the-box posture. Extra keys are recorded as a detail, never trusted.
- **Fallback plan:** when the required-only plan fails and the tfvars set
  optional values, the harness plans again with every tfvars value and scores
  from that plan. An optional variable whose default breaks the plan is a real
  interface defect, and it costs the `B3_plans_required_only` baseline item
  instead of the whole score.
- **Sandbox identity:** the model cannot know the sandbox's own identifiers,
  so every scoring plan substitutes them from the environment, as an operator
  would. For GCP fixtures, any string variable named `project`, `project_id`,
  `gcp_project` or `google_project` takes `GOOGLE_PROJECT`. For Azure
  fixtures, any string variable named `resource_group`,
  `resource_group_name`, `rg` or `rg_name` takes `AZURE_RESOURCE_GROUP`, the
  sandbox's application resource group, and any named `subscription`,
  `subscription_id`, `azure_subscription_id` or `arm_subscription_id` takes
  `ARM_SUBSCRIPTION_ID`. The value applies whether or not the
  tfvars set it, and the sweep leaves it alone. Lookups then resolve against
  the real project or resource group instead of a placeholder.
- Provider configuration comes from the environment (region, project or
  subscription, ambient credentials), not injected blocks, with one
  exception: azurerm cannot plan without a `features {}` block, which no
  environment variable supplies, so an Azure root module that declares no
  azurerm provider is planned with that minimal block added. The static lens
  reads the module as written. The Azure provider
  reaches storage data planes with Entra ID (`ARM_STORAGE_USE_AZUREAD`), so a
  storage account with shared-key access disabled can be created. Whether the model writes its own provider
  block is a design choice, neither required nor punished mechanically.
- `tofu` runs with the provider configuration variables (`AWS_*`, `GOOGLE_*`,
  `ARM_*`), its own `TF_*` settings and basic process variables such as
  `PATH` and `HOME`; nothing else from the harness environment reaches it.
- `examples/` may be shipped as documentation (the judge reads source), but it
  is not part of the mechanical evidence chain.

**Functional gate (layer 1):** the module `init`s and `plan`s as a root module
with its own tfvars, filtered to required-only, or in full when only the
fallback plan succeeds. A tfvars that fails to parse, omits a required
variable other than a substituted identity, or fails both plans fails the
gate with a recorded reason.

Planning stands in for applying, and some configurations plan cleanly but are
rejected by the cloud API at create time. A fixture lists the ones its brief
leads into under `apply_failures`: each entry has an `id`, a `description`,
the `evidence` of an observed apply error, and a `check` in the same
vocabulary as rubric items, evaluated against the defaults plan. Entries
are added only after the failure has been reproduced against the real API.

A module that matches an entry passes the gate and is scored in full; its
rubric, mechanical and composite scores are then multiplied by 0.5
(`APPLY_FAILURE_FACTOR`), with the unmultiplied values kept as
`raw_semantic_score` and `raw_mechanical_score`. The attempt fails its
verdict and is reported as a finding. The factor ranks every module that
cannot be applied below every working module of passable quality, while
keeping the quality differences among the failures visible. A plan failure
stays a gate failure scored 0: the model had `tofu_plan` and could have seen
it, whereas an apply failure gives the model no signal, and most rubric
items need a plan to evaluate at all.

The contract requirement is public and functional; stating "ship a
minimal.tfvars with literal values for required variables" in the prompt
leaks no rubric content.

## Two evidence lenses

The static lens parses source with HashiCorp's HCL library (`tools/hclast`, the
parser OpenTofu itself uses), which reports each attribute's literal value, the
references it makes and its expression tree. Static checks never evaluate
expressions: `local.strict`, ternaries, `merge()` calls all arrive as `"${...}"`
expression text. Tofu's evaluator is the only trustworthy one, and plan JSON is
its output; the solver evaluates expression trees only to propose inputs for a
plan to confirm (see Solve-then-confirm).

The static lens reads the module as deployed: every local module it calls
(`source = "./..."`) joins the root's source. The child's resources, data
sources and locals appear under names prefixed with the call's label, each
`var.<name>` inside them reads as the call's argument (or the child
variable's default), and the child's variables, outputs and provider settings
stay out, so interface checks see only the root's. Directories the module never
calls, such as examples, are not read.

So every check declares which lens it looks through, chosen by what the question is:

- **Static HCL lens** (`hclq`, parsed source) — questions about *how the code
  is written*: is this attribute a hardcoded literal; is it fed by any
  variable; is the resource's existence conditional; does the interface
  respect the budget; does the source contain this policy principal.
- **Plan lens** (plan JSON at required-only inputs, plus the sweep) —
  questions about *what the code does*: is versioning on, does a lifecycle
  rule exist, is logging wired. Static parsing would misjudge these whenever
  the model used locals, ternaries, or `dynamic` blocks — plan JSON resolves
  them all.

## Attribute postures

A rubric item may declare a posture naming the philosophy its check encodes:

| Posture | Meaning | Evidence |
|---|---|---|
| `hardcoded` | Security posture. An input that can weaken it is the defect, even with a safe default; a choice between secure settings is not. | Static lens: every value the source can produce is secure (`closed_values`: a literal, or a conditional or confined input whose every value is secure); no variable taint on existence (`count`/`for_each`/`dynamic`). The sweep corroborates (below). |
| `default_on` | Safe out of the box, legitimately reversible. The off state is silently harmful and consumers won't know to opt in; hardcoding is wrong because turning it off is sometimes legitimate. | Graded ladder (below). |
| `budget` | Interface size fits the audience. Graded, never a cliff. | `budget: {soft, hard}` — full credit at or under `soft` declared variables, linear to zero at `hard`. |
| `ladder` | Ordered alternatives where one mechanism is better than another that still works. | `ladder: [{score, check}, ...]` — the score of the best rung whose check passes, 0 when none does. |
| `reachable` | Must be *offered*; mechanism is the model's choice. | Present in the defaults plan **or** in at least one perturbation-sweep plan. |

`reachable` is where mechanism-neutrality lives: a direct `enable_logging`
boolean, an `environment`-inferred setting, and a locals-routed derivation all
pass identically — the sweep observes outcomes, not interface style. Whether
one interface is *better* stays in the judge layer, where design taste
belongs. Classifying a given attribute is per-fixture authorship, made in the
YAML and defended by the reference matrix like every other rubric judgment.

Besides `budget` and `ladder`, `default_on` is graded because its design
space is ordered — "protects you unless you opt out" beats "protects you if
you thought to ask," which beats "inflexible or missing" (canonical cases:
deletion protection, backups):

- **1.0** — present in the defaults plan, with variable influence proving an
  opt-out exists.
- **0.5** — absent at defaults but reachable through some input (opt-in only).
  The fraction is overridable per item (`partial: 0.4`).
- **0.0** — absent everywhere; or hardcoded in either polarity. Hardcoded-off
  never protects; hardcoded-on blocks legitimate operations (a permanently
  deletion-protected database cannot be destroyed through OpenTofu) — the
  very reason the attribute isn't posture `hardcoded` in the first place.
  An item sets `hardcoded_on: 0.75` when the brief makes that cost minor
  next to the protection: hardcoded-on costs only flexibility (backups:
  storage cost, no obstacle to retiring the resource), or the brief
  describes resources whose loss outweighs the friction of retiring them
  (deletion protection on production databases holding customer data).
  That credit sits above opt-in and below a real opt-out.

Where a service offers more than one legitimate mechanism for the same
protection, `behavior:` may list them; the best-graded alternative counts.

This is the opt-out-sentinel doctrine from `good-opentofu.md` made
mechanical: destructive or protective defaults ship safe, with a documented
escape hatch.

## The perturbation sweep

The sweep is **interface-driven**: it enumerates the module's *declared
variables*, perturbing each from its default (or its tfvars value for
required ones). Candidate values come from the variable's validation block —
a `contains([...])` allowed-values validation supplies the candidate list —
or from the value's type; fixtures may add candidate hints in YAML
(`perturb: {environment: [dev, staging, prod]}`). Perturbations rejected at
plan time are recorded and excluded from evidence: a validation refusing a
value is good design, not a penalty.

The sweep serves two symmetric roles:

- **Universal quantifier for `hardcoded` items** — in *no* reachable plan does
  the posture weaken. Static analysis is the primary evidence; the sweep is
  the cross-check against indirections the static analysis cannot see.
- **Existential quantifier for `reachable` items** — in *some* reachable plan
  the capability appears.

Bounded search is strong evidence, not proof; recorded honestly.

## Solve-then-confirm

A one-variable sweep cannot reach a capability whose input the module
guards with a second input: zone balancing that a precondition allows only
with three or more instances, or an observability resource created only
when a workspace ID is supplied. For every `resource` check that accepts
*some* sweep plan (`plans` includes `sweep`, `quantifier: any`), belongs to
a rubric or expertise item that fails on the defaults plan and the sweep,
and is itself missed by both, the solver (`solve.py`) searches the source
for inputs that reach it, and the harness plans what it finds.

- **Evaluation.** The Go helper exports every expression's tree. The solver
  evaluates variables (with `optional()` object defaults), locals, `count`,
  `for_each`, `dynamic` blocks and common functions over candidate inputs.
  Resource attributes, data sources and unmodeled functions are unknown: a
  goal is never met through an unknown, and an unknown guard does not block
  a witness.
- **Candidates.** Each input leaf, including attributes of object-typed
  inputs, draws values from the module's own source: the literals it is
  compared against (and their neighbours for ordering comparisons), the
  values a `contains([...])` lists, the keys of maps it indexes, and both
  values of a bool, at any depth of an object. The numeric attributes of one
  object share their constants, so a minimum and a default bounded against
  each other can rise together. Fixtures supply `samples`, keyed by
  `type.attr`, for values the source cannot provide, such as a well-formed
  resource ID; an input that feeds that attribute directly tries the sample.
- **Null objects.** An object input that defaults to `null` is tried as a
  whole value: required strings from samples, the source's literals or a
  placeholder, numbers from the source's constants or 1, bools false, and
  optional attributes omitted. Its attributes vary only once it is set. An
  object with a required attribute of any other type is left at `null`.
- **Search.** Assignments are tried with the fewest changed inputs first (at
  most three). A witness meets the goal and fails no variable validation
  and no resource or output precondition. A guard that already fails at
  defaults is an evaluator blind spot, since that plan succeeded, and is
  ignored.
- **Confirmation.** The harness plans up to three witnesses per goal and
  stops at the first whose plan meets it. Every plan that succeeds joins the
  sweep plans as evidence of an input the module accepts, so every
  sweep-quantified check sees it. Each attempt and its outcome is recorded
  in the result's details.

The source proposes and the plan decides: a witness the solver gets wrong
costs one rejected plan, never a wrong score.

## The check engine: generic verbs, YAML parameters

`generation.py` is an engine: fixture loading, the gate, the probe harness,
and a dispatcher into the verb vocabulary. All service knowledge lives in
`rubric.yaml`. The vocabulary is small and closed:

| Verb | Lens | Asserts |
|---|---|---|
| `resource` | plan | resources of `type` exist and match `where` predicates (nested blocks, literal equality, `{exists: true}`, `{in: [...]}`, `{gte: n}`/`{lte: n}` on numbers and numeric strings, `{contains: x}` on lists, `{matches: regex}` on strings); `match: any\|every` over instances; `min_instances: n` requires that many matching instances and `min_regions: n` that they sit in that many distinct regions (the planned `region` attribute, or else the resource's provider configuration: a literal, a variable or an attribute of one, or the environment's `AWS_REGION` when it sets none); `plans: [defaults, sweep]` with `quantifier: any\|all` over plans; `if_present: true` lets a plan without the type pass, so an optional resource is held to `where` only when it is planned |
| `hardcoded` | static | at least one resource of `type` exists whose existence is unconditional (no variable taint on `count`/`for_each`) and whose `attrs` are literals equal to the required values (`attrs_exist` only requires presence). Attribute names may be dotted paths through nested blocks; a `dynamic` block on the path is a knob unless its `for_each` is a non-empty literal (it always renders, so its content reads like a static block); `{in: [...]}` accepts any listed literal |
| `declares` | static | the source declares at least one resource of `type`, gated or not — lets an item pass modules that never create the thing it guards |
| `expr_matches` | static | every resource's `attr` expression (a dotted path reaches into nested blocks), resolved through locals, data sources and variable defaults (`var.x` reaches x's default; `var.x.a` and, through the resource's `for_each`, `each.value.a` reach attribute a of that default and any `optional(T, DEFAULT)` default for a in x's type), matches `pattern` — or the resource has `or_attr_present` instead |
| `var_feeds_attr` | static | some declared variable feeds the named attribute (at any nesting depth, dynamic blocks included), transitively through locals, through `each.key`/`each.value` to the resource's `for_each`, and through a dynamic block's iterator to that block's `for_each` (an index such as `x[each.key]` does not carry it); `has_default: true` restricts to optional variables; `type` restricts to one resource type; `through_data: true` also follows data-source lookups keyed by a variable |
| `closed_values` | static | every value the source can produce for each of `attrs` on every instance of `type` equals the required value (or is `{in: [...]}`): a literal, or an expression whose every conditional branch, map value and input domain is one, where an input's domain is both values of a bool or the literal set a validation confines it to (`contains([...], var.x)`, `var.x == lit`, and their `\|\|`/`&&` combinations). A choice between secure settings passes; any other input, function or reference is open and fails, as does a missing attribute or a `dynamic` block on the path whose `for_each` is not a non-empty literal. At least one instance must exist unconditionally, as with `hardcoded`. A proof from the source, so it needs no sweep |
| `var_feeds_provider_attr` | static | some declared variable feeds the named attribute of a provider configuration block (nested blocks such as `default_tags` included), transitively through locals; `provider` restricts to one provider; `has_default` as above |
| `provider_constraints` | static | required_providers is declared and every constraint excludes the next major version |
| `plans_required_only` | harness | the defaults plan succeeded with only the required inputs, not through the fallback plan |
| `source_contains` | static | needle appears in module source (policy principals, condition keys) |
| `output_named` | static | an output exists whose name/value matches |
| `interface` | static | structural constraints: variable count budget, descriptions required on every variable and output |
| `all_of` / `any_of` / `not` / `ref` | — | combinators; `ref` reuses another item's result |

Note: the plan-target field is spelled `plans:`, not `on:` — an unquoted `on`
key parses as boolean True under YAML 1.1.

**Baseline items** (`fixtures/generation/baseline.yaml`) are universal checks
— true of any OpenTofu module regardless of service or brief — merged into
every fixture's items by the engine, with no per-fixture opt-out. Entries must
be fixture-independent and use the static lens or a harness fact; they carry `B`-prefixed ids so
reports keep rubric (`H*`), audience-fit (`A*`), baseline (`B*`), and
expertise (`E*`) provenance legible, and they pool into the mechanical score
at their declared weights. A baseline `mandatory:` list joins every fixture's
mandatory items. An item marked `penalty: true` weighs 0: passing it earns
nothing, and failing it multiplies the composite by 0.5, as a known apply
failure does. Penalty items are for defects no module should have, whose
absence is no achievement (a module that creates nothing passes them).

Rules that keep this from rotting:

- **Verbs must be service-agnostic.** The same rule that governs
  `good-opentofu.md`: service knowledge lives in fixture YAML (and expertise
  checklists), never in the engine. An `s3_bucket_uniqueness` verb would be
  a junk drawer one layer down; the generic form is `expr_matches` with
  parameters.
- **No per-fixture Python.** A check the vocabulary cannot express is a
  signal to design one new generic verb, with selftest coverage — a
  deliberate, rare event. The invariant: adding or activating a fixture
  touches only its own `fixtures/generation/<ID>/` directory.
- Expertise items use the same verbs: each `expertise:` entry in
  `rubric.yaml` carries a `check:` block, scored as a separate unweighted
  subscore.

A representative item (see `fixtures/generation/G001/rubric.yaml` for the
full set):

```yaml
- id: H9
  weight: 4
  posture: reachable   # logging offered; mechanism is design choice
  check:
    resource:
      plans: [defaults, sweep]
      quantifier: any
      type: aws_s3_bucket_logging
```

## What this deliberately does not claim

Hardcoding-only scoring cannot distinguish "secure because the model
understood" from "secure because the model copied a hardened snippet." That is
the judge layer's and the expertise checklist's job. The mechanical layer's
job is to be **ungameable**, and "the static code is secure with no opt-out"
is the most ungameable form of the criterion.

Scoring how well a model *consumes* an existing knob-laden module (variable
selection against a fixed module) is a different skill and out of scope for
the generation domain.

## The safety net

Selftest keeps declarative checks honest exactly as it keeps Python checks
honest: each fixture ships a reference matrix (intentionally different good
designs plus targeted bad ones), the good references must pass every
mandatory item and outscore every bad one, and each bad reference must fail
the specific items it was built to fail. A misdeclared YAML check breaks the
matrix and fails selftest.
