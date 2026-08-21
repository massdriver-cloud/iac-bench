# Generation evaluation design (draft for review)

**Status:** implemented, with one major revision — the mechanical layer
(layer 2) described here was superseded by root-module evaluation and the
declarative check engine; see `generation-check-engine.md` for the current
mechanics. The layer model, brief philosophy, expertise checklists, reference
matrix, and judge layer below remain current.
**Domain:** `generation` (Tier 2, real AWS)
**First fixture:** G001

## Why generation is scored differently

Fix-domain fixtures have a binary ground truth. Generation does not: the interesting
qualities are *which* concepts were variablized, *which* inputs are guarded, what expertise
the module encodes. Generic scalar metrics (validation %, variable counts, "pass-through
index") are SLOC-like proxies — they describe the population, not the instance — so they are
**recorded but never weighted**.

## The layers

| Layer | What | Nature | Contributes to score |
|-------|------|--------|----------------------|
| 1 | Functional gate: init/validate/plan/apply of the module's own examples | mechanical, boolean | prerequisite — quality layers only run if this passes |
| 2 | Brief-specific semantic checks (the rubric) | mechanical, itemized, weighted | yes — the main mechanical score |
| 3 | Pairwise judgment on the open design space | LLM-judge, validated against human ranking first | yes — separate column, never silently merged |
| 4 | Generic stats (var counts, validation %, locals depth, checkov findings) | mechanical, scalar | no — descriptive columns only |

Composite scoring policy is a **versioned artifact** (`scoring_policy: v0`), recorded into
every result. Proposal for v0: `semantic = weighted fraction of rubric items passed`,
`judged = normalized pairwise preference`, published side by side plus a composite
`0.6 * semantic + 0.4 * judged`. Weights and the split are expected to change; re-scoring
stored outputs under a new policy costs nothing.

## Brief philosophy (scoring_policy v1): measure what the model volunteers

Briefs are short, realistic human prompts — 2–5 sentences: what is needed, why, who will
use it, and at most 1–2 requirements that are genuinely critical to the design. Real users,
especially non-experts, do not enumerate security and lifecycle requirements; a brief that
spells out "private, encrypted, versioned, 30-day floor, ≤8 inputs" converts the most
valuable signal — does the model *know* to do these things — into an instruction-following
check, and collapses the variance we are trying to observe.

Consequently the rubric items are **hidden criteria**. Nothing scored appears in the brief.
Privacy, encryption, name uniqueness, lifecycle hygiene, versioning, logging, tagging, and
interface restraint are all volunteered or not. This also changes what some old items could
be: with no stated org policies there is no ground truth for "correct" input bounds, so
input-guard checks (was the *right* variable validated) moved from the mechanical layer to
the judge. Do not leak rubric content into briefs or the scaffold prompt.

Corollary: brief edits invalidate prior results for that fixture exactly like fixture edits
do — the v0-brief runs are not comparable to v1 runs.

## How rubric checks stay mechanical without prescribing the design

The brief mandates a small set of org-standard input names (`environment`, `team`) — this is
realistic (platform teams standardize these) and gives probes an anchor. Everything else is
discovered, not assumed:

- **plan_assert** — instantiate the module's own minimal/prod examples, assert properties in
  plan JSON (encryption on, public access blocked, tags present, name convention).
- **probe_positive (perturbation)** — for behaviors the brief says must be tunable: enumerate
  the module's documented variables, perturb each by type (numbers bumped, booleans flipped,
  strings from candidates), diff plans, and assert *some* input moves the target behavior.
  Name-agnostic: any well-designed interface passes, a wrong-knobs interface cannot.
- **probe_negative_reject** — instantiate with a value the brief forbids (e.g. lifecycle
  transition below the org floor), assert validate/plan fails. Checks that the *right*
  variables are guarded — not what fraction of variables have validation blocks.
- **no_reachability** — for attributes consumers must not control (encryption, public
  access): static check that the attribute is not derived from any variable, backed by the
  perturbation sweep asserting no documented input weakens it. (Bounded search — this is
  strong evidence, not proof; noted honestly in the record.)
- **interface** — structural constraints stated in the brief itself (e.g. input count cap),
  so the model was told the rule it's being scored against.

## Expertise checklists: discovered, comparative, unweighted

Service-specific expert touches (BucketOwnerEnforced, multipart cleanup, log-delivery
policies) are the strongest tiebreaker between candidates that pass the whole core rubric —
but the space is open-ended and any authored list is capped by its author's knowledge. So:

- Each fixture's rubric carries an `expertise:` section — mechanically verifiable touches,
  each recording `discovered_via` provenance. Scored as a **separate subscore/column**
  ("expertise: k/n known touches"), never folded into the semantic score: the core rubric
  answers "did it meet the bar," expertise answers "how deep does its knowledge go."
- **The list grows by discovery, not authorship.** Judge rationales explicitly name the
  differentiators they weighed; after judged batches, mine those citations, approve the
  real ones, and they become permanent checklist items. The judge discovers once; the
  checklist remembers forever.
- **Qualification rule:** an expertise item must not invent an uncommunicated use-case or
  capability (see good-opentofu.md → Unstated assumptions for the line). Inputs are fine
  when they parameterize core capabilities of the requested service. Borderline touches
  (e.g. CORS — assumes a browser consumer) stay judge-territory.
- The report renders an **expertise differential table** per fixture — every known item ×
  every candidate, present/absent — both as user-facing insight and as the raw feed for
  checklist curation.

## Descriptive statistics (informational, unscored)

Reports also carry per-attempt stats that are interesting but never scored: wall-clock
duration, token usage, **estimated cost** (computed from `prices.yaml`, a versioned price
snapshot — estimates are labeled with the snapshot date), Terraform SLOC, and
comment-to-code ratio. These are layer-4 columns in the SLOC-caveat sense: descriptive,
gameable, deliberately weightless.

## Anti-taste defense: the reference matrix

Rubric items are authored judgment; the defense is the `correct_alt` principle scaled up.
Each generation fixture ships intentionally *different* reference implementations:

```
testdata/solutions/G001/
  ref_lean/          # opinionated, ~5 inputs, heavy locals     -> must score high
  ref_flexible/      # ~8 inputs, more configurable, compliant  -> must score high
  bad_passthrough/   # 20+ inputs incl. ability to weaken security -> fails R3/R5/R11
  bad_minimal/       # bare bucket, no lifecycle/logging/policy  -> fails most items
  bad_unsafe/        # public-readable option exposed            -> fails R2/R3
```

Selftest asserts both refs pass all mandatory items and outscore every bad reference, and
that each bad reference fails the *specific* items it was built to fail. If a deliberately
good design flunks the rubric, the rubric is wrong.

## Judge layer (implemented, not yet trusted)

Blind pairwise comparisons ("given this brief, which module would you rather inherit?"),
each pair judged in both presentation orders, aggregated Bradley–Terry. Implemented in
`src/iacbench/judge.py`; prompt at `prompts/judge-pairwise.md` (hashed into every
judgment); run with `iacbench judge --candidates <dir> [--model <judge>]`.

The judge is anchored to `docs/good-opentofu.md` — the org's living definition of module
quality, owned by a human. It is appended to the judge's system prompt and its sha256 is
recorded in every judgment, so verdicts are attributable to a specific edition of taste.
Like the rubric, it is never shown to candidate models. The iteration loop: recurring judge
findings → new principles in the doc; principles that turn out mechanically checkable →
migrate down into rubric items; editing the doc re-anchors the judge (re-judging stored
candidates is cheap, re-generation is not needed).

Activation gate: a human ranks the same pairs (`iacbench judge --human <yaml>`); the judge
earns a report column only at ≥0.8 agreement. Until then `scores.json` is stamped
`experimental`. Known validity risks, mitigated by the gate rather than assumed away:
self-preference when the judge model authored a candidate, and verbosity/style bias.

**Why this layer exists (measured 2026-08-18):** Haiku and Sonnet both scored 1.0 on G001's
mechanical rubric — the mechanical layers verify competence but saturate at the frontier.
Pairwise judgment is the only instrument left that can rank outputs that both pass every
consequence check.

## Open questions for review

1. Interface cap at 8 — hard rubric item or brief guidance only?
2. Should the brief require an `examples/` directory (standard module practice, and it gives
   the harness the model's own intended usage), or should the harness synthesize instantiations?
   Current draft: require examples.
3. Perturbation sweep runs `plan` per variable per candidate value (~20–40 plans per
   attempt). Fine on plan-only; do we ever need probe applies?
4. v0 composite split 60/40 mechanical/judged — placeholder, adjust freely.
