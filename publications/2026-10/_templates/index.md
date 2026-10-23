---
title: "iac-bench 2026-10: how well do language models write infrastructure modules?"
release: "2026-10"
published: 2026-10-23
---

# How well do language models write infrastructure modules?

**iac-bench release 2026-10 · published 2026-10-23 · 10 models · 3 clouds · 90 attempts**

We asked ten language models to write reusable OpenTofu modules for three common cloud
services:

- an S3 bucket for application teams (AWS);
- a Cloud SQL for PostgreSQL instance for a DBA team (GCP);
- an App Service web app for an SRE team (Azure).

Each request was a few sentences long, as it would be from a colleague. It never listed
the security, durability or hygiene requirements a senior reviewer would expect.

We scored the 90 resulting modules on two components:

- **Mechanical rubric (70%).** Fixture-specific checks evaluated against real `tofu plan`
  output.
- **Judge (30%).** A calibrated LLM judge grading design and craft against a published
  quality doctrine.

This article reports the results and the patterns behind them:

- [Methodology](./methodology.md): how it was done.
- [Scoring criteria](./scoring-criteria.md): the reference for every criterion ID used
  below.
- [Per-model reports](#per-model-reports): one page per model.

## Key findings

{{KEY_FINDINGS}}

## Leaderboard

{{LEADERBOARD}}

![Overall composite score with bootstrap 95% confidence intervals](./figures/fig1-leaderboard.svg)

*Figure 1. Overall composite (mean of the three per-fixture medians). Whiskers show the
bootstrap 95% CI; the right-hand labels give the 95% rank interval.*

**How to read the ranking.** Three samples per model per fixture is enough to separate
groups but not neighbors:

- **Top group:** {{TOP_GROUP}}. Their rank intervals overlap.
- **Clearest separation:** Claude Opus 5.5 is the only model whose interval (1–3) stays
  within the top three.
- **Bottom:** Gemini 3.6 Flash ranks last in at least 95% of bootstrap draws.
- **Middle:** the remaining models overlap one another.

Claude Haiku 5.5's interval is the widest in the release. It is driven by one fixture where
two of three modules failed to plan. Pairwise win probabilities are in the data release.

## Results by fixture

![Composite median by fixture](./figures/fig3-fixtures.svg)

*Figure 2. Median composite of three attempts, per model and fixture.*

{{FIXTURE_TABLE}}

Fixture scores are not interchangeable. **G001 (S3)** punishes omission: the brief's
audience is developers who "don't know S3 well," so every hygiene decision falls to the
module. The models that lose the most here:

- GPT-6 Astra and GPT-6 Luna build secure but minimal buckets, with no lifecycle rules and
  no access logging. That costs them up to a quarter of the rubric.
- Gemini 3.6 Flash and DeepSeek V4 Pro expose the public access block as an input.

**G002 (Cloud SQL)** rewards locking down a specialist's interface without taking their
controls away. **G003 (App Service)** depends heavily on two settings the Azure provider
leaves insecure by default.

## Finding 1: The same blind spots, across vendors

Some criteria were missed by nearly every model, regardless of vendor, size or overall
rank. These are the clearest signal in the release, because they do not depend on which
model you pick.

![Full-credit rate on the most-missed rubric items](./figures/fig5-items.svg)

*Figure 3. Share of attempts earning full credit on the rubric items most often missed,
by model. Item definitions are in [Scoring criteria](./scoring-criteria.md).*

{{BLIND_SPOTS}}

## Finding 2: Two ways to ship an insecure module

![Security findings and failed gates](./figures/fig6-findings.svg)

*Figure 4. Attempts with at least one mandatory security failure, and attempts that did
not plan, out of 9 per model.*

{{SECURITY}}

## Finding 3: The rubric and the judge catch different defects, and the ranking holds without either

![The two scoring components](./figures/fig4-components.svg)

*Figure 5. Mechanical-only and judge-only scores per model (mean of per-fixture medians).*

{{COMPONENTS}}

## Finding 4: Cost and capability are only loosely related

![Score versus generation cost](./figures/fig2-cost.svg)

*Figure 6. Overall composite against the estimated cost of one attempt at each fixture, at
list prices on 2026-10-23. The dashed line is the Pareto frontier: models no other model
beats on both cost and score.*

{{COST}}

## Finding 5: Documentation is where good modules lose points

{{DOCS}}

## Finding 6: One sample is not enough

{{VARIANCE}}

## Per-model reports

{{MODEL_INDEX}}

## Limitations

The main limitations of this release:

- **Plan-only.** Nothing was applied, so errors that only appear at apply time are not
  measured.
- **Three fixtures.** Results should not be generalized beyond these three services.
- **Three attempts per cell.** Neighboring models usually cannot be separated.
- **Undated model aliases.** Results are tied to the run date (2026-10-22).
- **A single judge from the same vendor as four candidates.** Mitigated by calibration and
  by reporting the mechanical score alone, not eliminated.
- **An opinionated doctrine.** Massdriver, which builds infrastructure tooling, wrote the
  briefs, rubrics and doctrine.

Full discussion: [Methodology §8–9](./methodology.md#8-limitations).

## Data and reproduction

The data release contains:

- every eval log and transcript;
- all 90 generated modules;
- every judge grade, with its evidence;
- the calibration reviews;
- the computed statistics.

It is licensed CC BY 4.0. The harness, fixtures, rubrics, reference modules and doctrine
are in the repository. Two scorer defects were found and fixed before publication; see
[Methodology §7](./methodology.md#7-errata-and-re-scoring).

## Citation

```bibtex
@misc{iacbench2026,
  title  = {iac-bench: Evaluating LLM-authored OpenTofu modules},
  author = {{Massdriver}},
  year   = {2026},
  month  = {10},
  note   = {Release 2026-10},
  url    = {https://github.com/massdriver-cloud/iac-bench}
}
```
