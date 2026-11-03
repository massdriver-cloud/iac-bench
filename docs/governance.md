# Benchmark governance

The rules this benchmark operates under. They exist so that a reader never has
to trust us — every claim is checkable, and the failure modes documented for
other leaderboards (private variant shopping, silent retractions, asymmetric
attempt budgets) are ruled out by policy rather than by promise.

## Runs and results

- **No retractions.** Every scored run of a listed model is published. A model
  never gets a do-over that deletes a bad run; re-runs add rows, they do not
  replace them.
- **No private variants.** A model appears on the leaderboard under exactly one
  pinned, dated identifier per row. Variants (thinking budgets, reasoning
  effort, snapshots) are separate rows, never averaged and never cherry-picked
  after the fact.
- **Identical treatment.** Every model gets the same fixtures, the same
  scaffold, the same prompts, the same attempt budget, and the same limits —
  all versioned in this repository.
- **Aggregates over draws.** Leaderboard numbers aggregate every
  current-edition attempt (median and range). A ranking claim is made only
  where ranges do not overlap; the report prints the minimum detectable
  difference so deltas below the benchmark's resolution are never presented
  as findings.

## Scoring provenance

- Every score records the scoring edition it was produced under (rubric hash,
  scaffold contract, tofu version, prices snapshot); attempts from older
  editions never pool into current aggregates.
- Judged scores record the judge model, its prompt hash, the doctrine edition
  hash, and the hash of the exact module snapshot graded. A judge grade joins
  the composite only while its stored calibration status is current; the
  calibration protocol, the human verdicts, and both raw and adjudicated
  agreement numbers are published.
- Mechanical scores never depend on the judge. A reader who rejects the
  published quality doctrine can use the mechanical columns alone.

## What this benchmark does not measure

- **Apply-time behavior.** Scoring is plan-only: apply-time cloud API
  rejections, idempotency under re-apply, and destroy behavior are not scored.
- **Consumption skill.** Selecting safe inputs for an existing knob-heavy
  module is a different skill from authoring; this benchmark measures
  authoring.
- **General coding ability, general intelligence, or fitness for any
  particular production use.** Scores are specific to the published fixtures,
  scaffold, and doctrine.
- **Provider operational quality** (latency, uptime, throughput). Run
  statistics are recorded as descriptive columns only.

## Contamination stance

All published fixtures, briefs, and reference solutions are public and may
enter future training corpora; scores on public fixtures should be read
accordingly. The record schema carries a `visibility: public | heldout` field;
held-out variants validate public-fixture scores, and rising public scores
that held-out variants do not corroborate indicate contamination, not
capability.

## Data

Published results are usable under CC BY 4.0. Raw transcripts and eval logs
for published runs are made available with each results release.
