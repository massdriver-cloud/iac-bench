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

**Versioning:** until the benchmark is published, scoring carries no version
history — all version fields (`scoring_policy` in rubric.yaml,
`SCAFFOLD_CONTRACT_VERSION`, `CHECK_DSL_VERSION`) are pinned at "v1", and a
scoring change simply invalidates older runs (stored candidates re-score for
free). Bump discipline — a change invalidates comparisons — begins at
publication.

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
- Provider configuration comes from the environment (region, project or
  subscription, ambient credentials), not injected blocks. Whether the model writes its own provider
  block is a design choice, neither required nor punished mechanically.
- `examples/` may be shipped as documentation (the judge reads source), but it
  is not part of the mechanical evidence chain.

**Functional gate (layer 1):** the module `init`s and `plan`s as a root module
with its own tfvars filtered to required-only. A tfvars that fails to parse,
omits a required variable, or plans nonzero fails the gate with a recorded
reason.

The contract requirement is public and functional; stating "ship a
minimal.tfvars with literal values for required variables" in the prompt
leaks no rubric content.

## Two evidence lenses

python-hcl2 parses syntax but does not evaluate expressions: `local.strict`,
ternaries, `merge()` calls all arrive as opaque `"${...}"` strings. Tofu's
evaluator is the only trustworthy one, and plan JSON is its output. So every
check declares which lens it looks through, chosen by what the question is:

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
| `hardcoded` | Security posture. A knob is the defect, even with a safe default. | Static lens: literal equals the secure value; no variable taint on the value **or on existence** (`count`/`for_each`/`dynamic`). The sweep corroborates (below). |
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
  never protects; hardcoded-on breaks legitimate operations (a permanently
  deletion-protected database cannot be destroyed) — the very reason the
  attribute isn't posture `hardcoded` in the first place. Where hardcoded-on
  costs only flexibility and blocks nothing (backups: storage cost, no
  obstacle to retiring the resource), the item sets `hardcoded_on: 0.75` —
  safer than opt-in, short of a real opt-out.

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

## The check engine: generic verbs, YAML parameters

`generation.py` is an engine: fixture loading, the gate, the probe harness,
and a dispatcher into the verb vocabulary. All service knowledge lives in
`rubric.yaml`. The vocabulary is small and closed:

| Verb | Lens | Asserts |
|---|---|---|
| `resource` | plan | resources of `type` exist and match `where` predicates (nested blocks, `{exists: true}`, literal equality); `match: any\|every` over instances; `plans: [defaults, sweep]` with `quantifier: any\|all` over plans; `if_present: true` lets a plan without the type pass, so an optional resource is held to `where` only when it is planned |
| `hardcoded` | static | at least one resource of `type` exists whose existence is unconditional (no variable taint on `count`/`for_each`) and whose `attrs` are literals equal to the required values (`attrs_exist` only requires presence). Attribute names may be dotted paths through nested blocks; a `dynamic` block on the path is a knob; `{in: [...]}` accepts any listed literal |
| `declares` | static | the source declares at least one resource of `type`, gated or not — lets an item pass modules that never create the thing it guards |
| `expr_matches` | static | every resource's `attr` expression, resolved through locals and data sources, matches `pattern` — or the resource has `or_attr_present` instead |
| `var_feeds_attr` | static | some declared variable feeds the named attribute (at any nesting depth, dynamic blocks included), transitively through locals and through `each.key`/`each.value` to the resource's `for_each` (an index such as `x[each.key]` does not carry it); `has_default: true` restricts to optional variables; `type` restricts to one resource type; `through_data: true` also follows data-source lookups keyed by a variable |
| `var_domain_closed` | static | the named attribute is fed by at least one variable, and every feeding variable is a bool or carries a `contains([...])` validation short enough for the sweep to plan every value; pair it with a sweep `resource` check so an input limited to safe choices counts as a decision, not a knob |
| `var_feeds_provider_attr` | static | some declared variable feeds the named attribute of a provider configuration block (nested blocks such as `default_tags` included), transitively through locals; `provider` restricts to one provider; `has_default` as above |
| `provider_constraints` | static | required_providers is declared and every constraint excludes the next major version |
| `source_contains` | static | needle appears in module source (policy principals, condition keys) |
| `output_named` | static | an output exists whose name/value matches |
| `interface` | static | structural constraints: variable count budget, descriptions required on every variable and output |
| `all_of` / `any_of` / `not` / `ref` | — | combinators; `ref` reuses another item's result |

Note: the plan-target field is spelled `plans:`, not `on:` — an unquoted `on`
key parses as boolean True under YAML 1.1.

**Baseline items** (`fixtures/generation/baseline.yaml`) are universal checks
— true of any OpenTofu module regardless of service or brief — merged into
every fixture's items by the engine, with no per-fixture opt-out. Entries must
be fixture-independent and static-lens only; they carry `B`-prefixed ids so
reports keep rubric (`H*`), audience-fit (`A*`), baseline (`B*`), and
expertise (`E*`) provenance legible, and they pool into the mechanical score
at their declared weights.

Rules that keep this from rotting:

- **Verbs must be service-agnostic.** The same rule that governs
  `good-opentofu.md`: service knowledge lives in fixture YAML (and expertise
  checklists), never in the engine. An `s3_bucket_uniqueness` verb would be
  a junk drawer one layer down; the generic form is `expr_matches` with
  parameters.
- **No per-fixture Python.** A check the vocabulary cannot express is a
  signal to design one new generic verb, with selftest coverage — a
  deliberate, rare event. The invariant: adding or activating a fixture
  touches only its own `fixtures/<domain>/<ID>/` directory.
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
