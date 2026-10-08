# Generation evaluation design

**Domain:** `generation` (Tier 2, real AWS, GCP, or Azure credentials per fixture, plan-only)

## Why generation is scored differently

Fix-domain fixtures have a binary ground truth. Generation does not: the interesting
qualities are *which* concepts were variablized, *which* inputs are guarded, what expertise
the module encodes. Generic scalar metrics (validation %, variable counts, "pass-through
index") are SLOC-like proxies — they describe the population, not the instance — so they are
**recorded but never weighted**.

## The layers

| Layer | What | Nature | Contributes to score |
|-------|------|--------|----------------------|
| 1 | Functional gate: the module plans as a root module with its own `minimal.tfvars`, filtered to required variables | mechanical, boolean | prerequisite — quality layers only run if this passes |
| 2 | Brief-specific semantic checks (the rubric), declared in each fixture's `rubric.yaml` and evaluated by the check engine — see `generation-check-engine.md` | mechanical, itemized, weighted | yes — the main mechanical score |
| 3 | LLM judge, validated against human verdicts: absolute 0–100 grading on the `good-opentofu.md` sections the rubric does not score, with blind pairwise comparison as a discovery tool | LLM-judge, gated | yes — separate column, never silently merged |
| 4 | Generic stats (var counts, validation %, locals depth, SLOC, cost) | mechanical, scalar | no — descriptive columns only |

The composite grade is 70% mechanical / 30% judged, per
`composite-scoring-policy.yaml` (a versioned artifact recorded into every report).
The mechanical component pools the rubric and expertise checklists into one
weighted fraction — rubric items carry their rubric weights, expertise items
weigh 1 each — so the rubric dominates by construction and the per-item worth
of an expertise entry does not swing with list sizes. Re-scoring stored
outputs under a changed policy costs nothing.

## Brief philosophy: measure what the model volunteers

Briefs are short, realistic human prompts — 2–5 sentences: what is needed, why, who will
use it, and at most 1–2 requirements that are genuinely critical to the design. Real users,
especially non-experts, do not enumerate security and lifecycle requirements; a brief that
spells out "private, encrypted, versioned, 30-day floor, ≤8 inputs" converts the most
valuable signal — does the model *know* to do these things — into an instruction-following
check, and collapses the variance we are trying to observe.

Consequently the rubric items are **hidden criteria**. Nothing scored appears in the brief.
Privacy, encryption, name uniqueness, lifecycle hygiene, versioning, logging, tagging, and
interface restraint are all volunteered or not. With no stated org policies there is also no
ground truth for "correct" input bounds, so input-guard checks (was the *right* variable
validated) belong to the judge, not the mechanical layer. Do not leak rubric content into
briefs or the scaffold prompt.

Corollary: brief edits invalidate prior results for that fixture exactly like fixture edits
do.

## Audience fit: interface size comes from the brief

Every brief names who will consume the module, and the fixtures deliberately span
audiences, from developers new to the service to specialist teams. There is no universal
variable budget. Each rubric carries hidden audience-fit items (`A*`):

- **Exposure:** controls this audience needs and would expect to own (a DBA team owns
  backup and maintenance windows; an app developer owns a name).
- **Restraint:** settings this audience would not understand or care about (an app
  developer is not asked to choose an encryption key).

- **Budget:** a graded interface budget per fixture — full credit at or under a soft input
  count, falling linearly to zero at a hard count — set from the brief's audience (narrow for
  developers new to the service, wide for a specialist team).

The budget is what keeps the benchmark from rewarding a race to expose every setting in order
to satisfy exposure checks: pass-through modules encode less expertise than modules tuned to a
use case. Restraint items naming settings the audience should never be handed, and the
hardcoded security items, punish pass-through shapes alongside it. Exposure and restraint are checked by what inputs feed (taint through locals), never by
variable names. Security posture is not an audience question: hardcoded security items
apply to specialist fixtures exactly as they do to beginner ones.

## How rubric checks stay mechanical without prescribing the design

The mechanics live in `generation-check-engine.md`; the property that matters here is
**name-agnosticism**. Checks assert outcomes (what the plan contains, what the source
hardcodes), never interface shapes: the perturbation sweep discovers which documented
input controls which behavior without knowing what the model called it, so a direct
boolean, an environment-inferred setting, and a locals-routed derivation score
identically. Any well-designed interface passes; a wrong-knobs interface cannot.

## Expertise checklists: discovered, comparative, unweighted

Service-specific expert touches (BucketOwnerEnforced, multipart cleanup, log-delivery
policies) are the strongest tiebreaker between candidates that pass the whole core rubric —
but the space is open-ended and any authored list is capped by its author's knowledge. So:

- Each fixture's rubric carries an `expertise:` section — mechanically verifiable touches,
  each recording `discovered_via` provenance. Reported as its own subscore/column
  ("expertise: k/n known touches") and pooled into the mechanical composite at weight 1
  per item: the core rubric answers "did it meet the bar," expertise answers "how deep
  does its knowledge go," and the pooling keeps the rubric dominant by construction.
- **The list grows by discovery, not authorship.** Judge rationales explicitly name the
  differentiators they weighed; after judged batches, mine those citations, approve the
  real ones, and they become permanent checklist items. The judge discovers once; the
  checklist remembers forever. An expertise item that proves universal enough to demand of
  everyone migrates into the core rubric.
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
  ref_lean/          # opinionated, few inputs, heavy locals      -> must score high
  ref_flexible/      # more configurable, doctrine-compliant      -> must score high
  bad_passthrough/   # many inputs incl. weakenable security      -> fails targeted items
  bad_minimal/       # bare bucket, no lifecycle/logging/policy   -> fails most items
  bad_unsafe/        # public-readable option exposed             -> fails privacy
```

Selftest asserts both refs pass all mandatory items and outscore every bad reference, and
that each bad reference fails the *specific* items it was built to fail (see the fixture's
`expectations.yaml`). If a deliberately good design flunks the rubric, the rubric is wrong.

## Judge layer

The judge is anchored to `docs/good-opentofu.md` — the org's living definition of module
quality, owned by a human. It is appended to the judge's prompt and its sha256 is
recorded in every judgment, so verdicts are attributable to a specific edition of taste.
Like the rubric, it is never shown to candidate models. The iteration loop: recurring judge
findings → new principles in the doc; principles that turn out mechanically checkable →
migrate down into rubric items; editing the doc re-anchors the judge (re-judging stored
candidates is cheap, re-generation is not needed).

**The judge grades only what the rubric cannot.** The doctrine's *Scored by the rubric*
section lists the sections the mechanical layer already scores (insecure configurations,
destructive defaults, unstated assumptions, tagging, versions, provider declarations). The
judge reads them as context but does not grade them, so a defect never costs a module in
both components. The judged 30% is design and craft: interface shape, variables,
structure, scope, outputs, documentation, and the like.

**Blind to authorship.** The judge sees the brief, the doctrine, and the module files —
never the model that wrote them.

Two modes, implemented in `src/iacbench/judge.py`:

- **Absolute grading** (`iacbench judge --grade`): each candidate scored per graded
  doctrine section independently — 0 no credit, 1 partial, 2 full, or NA (multiple
  samples, medians, one sentence of evidence per score) — and the weighted mean is
  normalized to 0–100. The scale is coarse on purpose: three levels are hard to blur
  together, and a human can check each grade at a glance. Roster-independent, so it is the judged component of the
  composite. Section scores are reported as their own table — one row per doctrine
  section, one column per candidate — so a reader who disagrees with a specific documented
  preference can discount exactly that row.
- **Blind pairwise** ("which module would you rather inherit?"), each pair judged in both
  presentation orders, aggregated Bradley–Terry. A discovery tool: its rationales feed the
  expertise checklist. It neither enters the composite nor takes part in calibration.

Every judge model grades every candidate. The judged component of the composite is the
median of the calibrated judges' grades; uncalibrated grades are shown, never folded in.

## Calibration

A grade joins the composite only after its judge is calibrated against the doctrine
owner (`iacbench calibrate`, one fixture at a time). The check is per cell — one module,
one doctrine section — because that is what the judge produces and what a person can
answer reliably: "are these variable descriptions good?" is quick; ranking two modules
across fourteen sections at once is not.

1. **Review sheets.** One sheet per module, under a blind label. It lists every graded
   section with each judge's grade and evidence side by side, then the module source.
   The human records their own grade (0, 1, 2 or NA) for every cell. Recording a grade
   rather than agree/disagree keeps the judges' answers from becoming the default, and a
   miss records how far off the judge was.
2. **Agreement.** Per judge: the share of cells where its grade equals the human's
   exactly (NA matches only NA), overall and per section. A judge is calibrated for the
   fixture at ≥ 0.8 overall agreement over at least 40 cells; each judge is gated on its
   own. A section the judges keep getting wrong is a signal to reword it in
   `good-opentofu.md` or drop it from the judged component.

Until a judge clears the gate, its grades are stamped `experimental` and stay out of the
composite. Known validity risks, mitigated by the gate rather than assumed away:
self-preference toward a judge's own vendor's models (which blinding does not remove when
a judge recognizes its own style), and verbosity or style bias.

**Why this layer exists:** the mechanical layers verify competence but saturate at the
frontier — strong models routinely pass every consequence check. Judgment against the
quality doctrine is the instrument that ranks outputs the rubric cannot separate.
