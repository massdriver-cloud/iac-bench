# Generation scoring: root-module evaluation and the declarative check engine

**Status:** implemented (2026-08-20) — engine in `src/iacbench/checks.py`,
harness in `src/iacbench/generation.py`, G001 restated and selftest-green.
One YAML lesson encoded: the plan-target field is spelled `plans:`, because an
unquoted `on:` key parses as boolean True under YAML 1.1.
**Scope:** generation domain only (G-fixtures). Fix domains are untouched.
**Versioning stance (2026-08-20):** the benchmark is unpublished, so scoring
carries no version history yet — whatever scoring is current is simply "v1",
and interface churn during design does not bump anything. All version fields
(`scoring_policy` in rubric.yaml, `SCAFFOLD_CONTRACT_VERSION`,
`CHECK_DSL_VERSION`) stay pinned at v1 until the benchmark goes live; bump
discipline (a change invalidates comparisons) begins at publication. Stored
candidates are simply re-scored under whatever is current — re-scoring is
free. Runs from before this redesign are invalid, full stop.

## The two problems this fixes

**1. The scorer measures variable choices, not the code.** Today's evidence
chain plans the module's own `examples/minimal` and `examples/prod` and asserts
properties of those plans. But the model wrote the examples — it is grading its
own homework. A module that variablizes a security attribute and sets it
safely in its examples scores identically to one that hardcodes the secure
setting, even though the first shipped a knob that makes the module
insecure-by-design. (The `no_reachability` items partially defend against
this; the `plan_assert` items do not, and behavioral items like versioning are
pure example-choice theater.) The unit under evaluation must be **the module
at its defaults plus the shape of its interface — never the inputs the model
chose to feed it.** What the model variablizes is a scoreable design decision;
what it sets variables to is not.

**2. `generation.py` is a junk drawer in the making.** It contains ~20
S3-specific helpers (`pab_ok`, `versioning_enabled`, `multipart_hygiene`, …),
13 closures hand-keyed to G001's item ids, hardcoded expertise lambdas, and
`environment`/`team` special cases in the perturbation code. Activating G002
(SQS) under this structure means a parallel set of SQS helpers and a second
registry, and so on for every fixture. Service-specific Python does not scale.

The fix for both is one redesign: evaluate the module as a **root module at
its defaults**, through a small vocabulary of **service-agnostic check verbs**
whose parameters live entirely in the fixture's `rubric.yaml`.

## Execution model: root module + model-supplied tfvars

The module is planned **as a root module**, never wrapped as a submodule in a
synthetic root. Rationale: per `good-opentofu.md`, terraliths are an
antipattern and the deliverable is a standalone root module — wrapping it as a
submodule tests exactly the consumption pattern the doctrine rejects. It also
eliminates the value-harvesting problem outright: the scaffold contract now
requires the model to ship a **`minimal.tfvars` (or `minimal.tfvars.json`)**
supplying values for its required variables, and tfvars values are literals by
definition.

Mechanics:

- The harness copies the module to a work dir, runs `tofu init` **once**, then
  executes every plan (defaults + full perturbation sweep) as repeated
  `tofu plan -var-file=<generated>.tfvars.json` in that dir. This replaces
  today's per-probe directory + per-probe init and is strictly faster.
- **Defaults plan:** the model's tfvars are parsed and **filtered to variables
  with no default** (`hclq.variables()` already knows which) before planning.
  Without this filter, optional values in the tfvars smuggle the model's
  choices back into what is supposed to be out-of-the-box posture — the exact
  leak this redesign exists to close. Extra keys are recorded as a detail,
  never trusted.
- Provider configuration comes from the environment (`AWS_REGION`, ambient
  credentials), not injected blocks. Whether the model writes its own provider
  block is a design choice, neither required nor punished mechanically.
- `examples/` may still be shipped as documentation (the judge reads source),
  but it exits the mechanical evidence chain entirely.

**Functional gate (layer 1) restated:** the module `init`s, `validate`s, and
`plan`s as a root module with its own tfvars filtered to required-only. A
tfvars that fails to parse, omits a required variable, or plans nonzero fails
the gate with a recorded reason.

This changes the scaffold contract (new required artifact, examples demoted);
per the versioning stance above, `SCAFFOLD_CONTRACT_VERSION` stays "v1" —
pre-publication, old runs are simply invalid. Contract requirements are public
and functional; stating "ship a minimal.tfvars with literal values for
required variables" in the prompt leaks no rubric content.

## Two evidence lenses

python-hcl2 parses syntax but does not evaluate expressions: `local.strict`,
ternaries, `merge()` calls all arrive as opaque `"${...}"` strings. Tofu's
evaluator is the only trustworthy one, and plan JSON is its output. So every
check declares which lens it looks through, chosen by what the question is:

- **Static HCL lens** (`hclq`, parsed source) — questions about *how the code
  is written*: is this attribute a hardcoded literal; is it fed by any
  variable; is the resource's existence conditional; does the interface
  respect the budget; does the source contain this policy principal.
- **Defaults-plan lens** (plan JSON at required-only inputs) — questions about
  *what the code does out of the box*: is versioning on, does a lifecycle rule
  exist, is logging wired. Static parsing would misjudge these whenever the
  model used locals, ternaries, or `dynamic` blocks — plan JSON resolves them
  all.

## Attribute postures

Every behavioral rubric item declares one of three postures. The posture
determines the lens, the quantifier, and the philosophy:

| Posture | Meaning | Evidence |
|---|---|---|
| `hardcoded` | Security posture. A knob is the defect, even with a safe default. | Static lens: literal equals the secure value; no variable taint on the value **or on existence** (`count`/`for_each`/`dynamic`). Sweep corroborates (see below). |
| `default_on` | Safe out of the box, legitimately reversible. The off state is silently harmful and consumers won't know to opt in; hardcoding is wrong because turning it off is sometimes legitimate. | Graded ladder (below): protection by default with a working opt-out earns full credit; opt-in-only earns partial; inflexible or absent earns none. |
| `reachable` | Must be *offered*; mechanism is the model's choice. | Present in the defaults plan **or** in at least one perturbation-sweep plan. |

`default_on` is the only graded (non-boolean) posture, because its design
space is ordered: "protects you unless you opt out" beats "protects you if
you thought to ask," which beats "inflexible or missing." The ladder:

- **1.0** — present in the defaults plan, *and* the sweep demonstrates an
  opt-out (some input turns it off).
- **0.5** — absent at defaults but reachable through some input (opt-in only).
  The fraction defaults to 0.5, overridable per item (`partial: 0.4`).
- **0.0** — absent everywhere; or hardcoded in either polarity. Hardcoded-off
  never protects; hardcoded-on breaks legitimate operations (a permanently
  deletion-protected database cannot be destroyed) — the very reason the
  attribute isn't posture `hardcoded` in the first place. Where a specific
  attribute makes hardcoded-on benign, the fixture expresses that item with
  plain `resource` checks instead of this posture.

This is the opt-out-sentinel doctrine from `good-opentofu.md` made
mechanical: destructive or protective defaults ship safe, with a documented
escape hatch. G001 has no `default_on` items (its candidates — versioning,
logging, lifecycle — are all `reachable` per review); the posture's first
expected use is a database-style fixture (deletion protection, backups,
point-in-time recovery).

`reachable` is where mechanism-neutrality lives: a direct `enable_logging`
boolean, an `environment`-inferred setting, and a locals-routed derivation all
pass identically — the sweep observes outcomes, not interface style. Whether
one interface is *better* stays in the judge layer, where design taste
belongs. Classification of a given attribute (`hardcoded`, `default_on`, or
merely `reachable`?) is per-fixture authorship, made in the YAML, and
defended by the reference matrix like every other rubric judgment.

`hardcoded` requires one `hclq` upgrade: today's taint analysis covers
attribute **values** but not **existence**. A model can hardcode a perfect
`aws_s3_bucket_public_access_block` and gate it behind
`count = var.enable_pab ? 1 : 0`. Taint must extend to `count`, `for_each`,
and `dynamic` block conditions or the posture is trivially dodged.

## The perturbation sweep, redesigned

The sweep becomes **interface-driven**: it enumerates the module's *declared
variables* (not the inputs an example happened to set), perturbing each from
its default (or its harvested required value). Candidate values come from the
variable's type and its validation block — an allowed-values validation hands
us the candidate list for free. The hardcoded `environment`/`team` cases in
`_candidates()` are deleted; fixtures may supply extra candidate hints in
YAML (`perturb: {environment: [dev, staging, prod]}`).

The sweep then serves two symmetric roles:

- **Universal quantifier for `hardcoded` items** — in *no* reachable plan does
  the posture weaken. Static analysis is the primary evidence; the sweep is
  the cross-check. If the sweep flips an attribute static taint called clean,
  that is a **scorer bug** (an indirection the static analysis missed) and it
  fails loudly in details, never silently passes the candidate.
- **Existential quantifier for `reachable` items** — in *some* reachable plan
  the capability appears.

As before, bounded search is strong evidence, not proof; recorded honestly.

## The check engine: generic verbs, YAML parameters

`generation.py` shrinks to an engine: fixture loading, the gate, the probe
harness, a verb registry, and a YAML→verb dispatcher. All service knowledge
moves into `rubric.yaml`. The verb vocabulary is small and closed:

| Verb | Lens | Asserts |
|---|---|---|
| `resource` | plan | resources of `type` exist / count; attribute-path predicates with `every`/`any` over instances and nested blocks; `plans: defaults \| sweep` with quantifier |
| `hardcoded` | static | attribute is a literal equal to the required value; existence unconditional; no variable taint (implies the sweep cross-check) |
| `expr_matches` | static | an attribute's expression, resolved through locals (`value_text_closure`), matches a pattern — e.g. name-uniqueness sources; `or_attr_present` escape (e.g. `bucket_prefix`) |
| `no_single_purpose_required_var` | static | no default-less variable feeds only the named attribute (today's H11, generalized) |
| `source_contains` | static | needle appears in module source (policy principals, condition keys) |
| `output_named` | static | an output exists whose name/value matches |
| `interface` | static | structural constraints: variable count budget, required-set predicates |
| `all_of` / `any_of` / `not` / `ref` | — | combinators; `ref` reuses another item's check |

Rules that keep this from rotting:

- **Verbs must be service-agnostic.** The same rule that governs
  `good-opentofu.md`: service knowledge lives in fixture YAML (and expertise
  checklists), never in the engine. A proposed `s3_bucket_uniqueness` verb is
  the junk drawer reforming one layer down; the generic form is
  `expr_matches` with parameters.
- **No per-fixture Python escape hatch.** A check the vocabulary cannot
  express is a signal to design one new generic verb, with selftest coverage —
  a deliberate, rare event.
- **The vocabulary is versioned** (`CHECK_DSL_VERSION`, alongside the scaffold
  contract): changing a verb's semantics invalidates comparisons. Pinned at
  "v1" until publication, per the versioning stance above.
- Expertise items get the same treatment: each `expertise:` entry in
  `rubric.yaml` grows a `check:` block using the same verbs; the hardcoded
  lambda table is deleted.

Illustrative G001 items restated (final wording happens in the rubric PR):

```yaml
- id: H1            # was H1+H2: privacy is a property, not a knob
  weight: 18
  posture: hardcoded
  assert:
    hardcoded:
      type: aws_s3_bucket_public_access_block
      attrs:
        block_public_acls: true
        block_public_policy: true
        ignore_public_acls: true
        restrict_public_buckets: true

- id: H6
  weight: 6
  posture: reachable
  assert:
    resource:
      plans: [defaults, sweep]
      quantifier: any
      type: aws_s3_bucket_lifecycle_configuration
      any: {rule: {transition: exists}}

- id: H9
  weight: 4
  posture: reachable          # logging offered; mechanism is design choice
  assert:
    resource:
      plans: [defaults, sweep]
      quantifier: any
      type: aws_s3_bucket_logging
```

Note the H1/H2 (and H3/H4) merges: under the `hardcoded` posture,
"secure in examples" and "not weakenable" collapse into one item — the old
split only existed because example plans were weak evidence.

## What this deliberately does not claim

Hardcoding-only scoring cannot distinguish "secure because the model
understood" from "secure because the model copied a hardened snippet." That is
the judge layer's and the expertise checklist's job. The mechanical layer's
job is to be **ungameable**, and "the static code is secure with no opt-out"
is the most ungameable form of the criterion.

## Alternatives considered and rejected

- **OPA/Rego over plan JSON** (conftest pattern): battle-tested, but a second
  language in the container, cannot express the sweep quantifiers or the HCL
  taint checks (those need `hclq`), and we would end up with Rego *plus*
  Python anyway.
- **Per-fixture Python check modules** (`fixtures/G00x/checks.py`): achieves
  "no changes to src/" but relocates the junk drawer into fixtures and makes
  the check surface unauditable.
- **All-static (no plan JSON at all)**: requires reimplementing Tofu's
  expression evaluator to see through locals/ternaries/dynamic blocks; false
  failures on well-written modules. Tofu already has the evaluator — the
  defaults plan *is* the static code, evaluated.
- **tree-sitter-hcl** instead of python-hcl2: real expression AST, but nothing
  yet needs structural expression reasoning; regex-over-`"${...}"` has held.
  Upgrade path if a check ever demands it, not now.

## Migration and invalidation

- G001's rubric is restated (postures, merged security items, `check:`
  blocks). **All stored G001 scores are invalidated**; stored candidates are
  re-scored for free. Expected movement: models that variablized security
  attributes with safe defaults drop.
- The reference matrix is re-reviewed under the new rule — `ref_flexible`
  especially, since "flexible" is now a liability anywhere it touched
  security. References gain `minimal.tfvars` files per the new contract.
- Selftest remains the safety net: a misdeclared YAML check breaks the
  reference matrix exactly like a wrong Python check does. Both refs must
  still pass all mandatory items and outscore every bad reference; each bad
  reference must fail the specific items it was built to fail.
- `good-opentofu.md` should carry the general principle (human-owned wording;
  no service examples per its standing rule): security posture is a property
  of the module, not a knob it offers — flexibility belongs to behavior,
  never to safety.
- **Acceptance test for the whole redesign: promoting G002 from
  `rubric-draft.yaml` to active touches only `fixtures/generation/G002/`.**
  If that holds, the design is proven. G002's J-checks are written in the
  new declarative form from the start — never in the old registry form.

## Deferred (recorded, not built)

**Secure-consumption domain (C-fixtures):** the inverse skill — given a fixed,
knob-laden third-party-style module and a brief, score only the model's
instantiation (variable selection). Legitimately different from authoring,
reuses the fix-domain scaffold almost unchanged, and is most working
engineers' daily Terraform. Parked so it does not complicate generation.

## Review resolutions (2026-08-20)

1. **Merged-item weights: straight sums** (H1+H2 → 18, H3+H4 → 14). The
   merge changes bookkeeping, not importance — privacy and encryption keep
   exactly the share of the rubric they already had; only the item count
   shrinks. A ground-up re-balance of all weights is deferred until scoring
   data argues for one.
2. **G001's versioning, logging, and lifecycle are all `reachable`.**
   `default_on` was briefly dropped as a strict subset of `reachable`, then
   reinstated as a *graded* posture once the deletion-protection/backup case
   showed the distinction carries real signal (protects-by-default vs
   protects-if-you-asked). Partial credit for opt-in-only per the ladder in
   the postures section. No G001 item uses it.
3. **`scoring-policy.yaml` is renamed `composite-scoring-policy.yaml`**
   during implementation (report loader updated in the same change), ending
   the naming collision with the per-fixture `scoring_policy` field.
4. **tfvars: both formats accepted** — `.tfvars` (python-hcl2 parses HCL
   tfvars natively) and `.tfvars.json` (stdlib). Harness-generated probe var
   files remain JSON either way.
