---
title: "iac-bench methodology"
release: "2026-10"
published: 2026-10-23
benchmark_version: "suite v0.1.0 · scaffold contract 1 · scoring policy v1 · doctrine af3ae1dd9fdc1c0c"
---

# iac-bench methodology

**Release 2026-10 · published 2026-10-23**

This document describes how the 2026-10 iac-bench results were produced: what the models
were asked to do, how their output was scored, how the scores were aggregated, and what
the numbers cannot tell you. The results are in [the 2026-10 results article](./index.md).
Every scored item is defined in [the scoring criteria reference](./scoring-criteria.md).

## 1. Goals and scope

iac-bench measures how well a language model writes **reusable infrastructure-as-code
modules** for OpenTofu (the open-source Terraform fork). A model gets a short request of
the kind a platform engineer receives from a colleague, and must deliver a module another
team could adopt.

Producing configuration that plans is the minimum. The benchmark measures what a senior
reviewer would look for:

- Is the module secure without being asked?
- Does it protect data from accidental loss?
- Does it give its audience the right controls, and no more?
- Does it encode service-specific expertise?
- Is it built the way experienced module authors build modules?

The 2026-10 release covers **module generation only**, on three fixtures, one per major
cloud. The repository also contains repair ("fix") fixtures. They are excluded from this
release because every model tested passes all of them, so they cannot separate models.

## 2. Task design

### 2.1 Fixtures

| Fixture | Cloud and service | Audience named in the brief | Interface budget |
|---|---|---|---|
| G001 | AWS · S3 bucket | Application developers who "fill in a couple of obvious inputs" | 8 inputs (zero credit at 16) |
| G002 | GCP · Cloud SQL for PostgreSQL | A DBA team that "knows PostgreSQL and Cloud SQL deeply" | 25 inputs (zero credit at 35) |
| G003 | Azure · App Service (Linux, containers) | An SRE team that "knows Azure well" | 20 inputs (zero credit at 30) |

Each fixture is defined by a brief, a rubric, and a reference matrix. All three are
published in the repository under `fixtures/generation/` and `testdata/solutions/`.

### 2.2 Briefs: measuring what the model volunteers

Briefs are short, realistic requests of two to five sentences. They state what is needed,
who will use it, and the one or two facts about the environment that settle the design: for
G002, that each environment already has its own VPC with private services access, and that
every engineer and workload has a Google identity.

Briefs **do not list security, durability, or hygiene requirements.** Real requests rarely
do, and listing them would turn the most valuable signal (does the model know to do these
things?) into an instruction-following check. The rubric's criteria are therefore hidden
from the model, but each core criterion is held to a rule: it must follow either from the
brief or from practice that is universal for the service. A model is never penalized for
failing to guess a preference the brief leaves open. Service-specific touches that go
beyond universal practice are scored separately as *expertise* (§4.3).

### 2.3 Evaluation setup

Each model works as a tool-using agent in an isolated working directory, using the
[Inspect](https://inspect.aisi.org.uk/) framework. Every model gets the same system prompt
(`prompts/generate-module.md`), the same tools, and the same limits.

| Setting | Value |
|---|---|
| Tools | `list_files`, `read_file`, `write_file`, `tofu_validate`, `tofu_plan`, `tofu_fmt`, `submit` |
| Deliverable | A root module (`*.tf`) plus `minimal.tfvars`, which gives a literal value for every variable without a default and must plan cleanly |
| Remote modules | Not allowed (calling one fails the evaluation); local submodules allowed |
| Limits | 150 messages, 30 minutes wall clock per attempt |
| API retries | Up to 3 per request, then the attempt ends as an error (none occurred) |
| Planning | `tofu plan` against real cloud accounts (AWS, GCP, Azure sandboxes). Nothing is ever applied. |
| OpenTofu | 1.12.5 |
| Providers | Each module's own version constraints, resolved at run time |

The `tofu_plan` tool plans against the same real cloud accounts used for scoring, so a
model can verify that its module plans before submitting.

### 2.4 Models and settings

| Model | API identifier | Access | Weights |
|---|---|---|---|
| Claude Opus 5.5 | `claude-opus-5-5` | Anthropic API | Closed |
| Claude Fable 5.1 | `claude-fable-5-1` | Anthropic API | Closed |
| Claude Sonnet 5.5 | `claude-sonnet-5-5` | Anthropic API | Closed |
| Claude Haiku 5.5 | `claude-haiku-5-5` | Anthropic API | Closed |
| GPT-6 Astra | `gpt-6-astra` | OpenAI API (Responses) | Closed |
| GPT-6 Luna | `gpt-6-luna` | OpenAI API (Responses) | Closed |
| Gemini 3.1 Pro | `gemini-3.1-pro-preview` | Google Gemini API | Closed |
| Gemini 3.6 Flash | `gemini-3.6-flash` | Google Gemini API | Closed |
| Kimi K3 | `moonshotai/kimi-k3` | OpenRouter | Open |
| DeepSeek V4 Pro | `deepseek/deepseek-v4-pro-0813` | OpenRouter | Open |

All models ran with their providers' default sampling and reasoning settings. No
temperature, reasoning-effort, or token-budget overrides were set. The GPT-6 models were
called through OpenAI's Responses API, because its Chat Completions API rejects tool use
combined with reasoning for these models. It changes only the API used, and no model setting.

**Pinning.** Except for DeepSeek V4 Pro (`-0813`), the providers' APIs returned these
identifiers as undated aliases, and none reported a dated snapshot. Results are therefore
tied to the run date: all generations ran on **2026-10-22**, and all judging on
**2026-10-23**. Hosted models can change behind an alias without notice.

### 2.5 Sampling

Each model ran each fixture **three times**, as independent attempts with no shared state:
10 models × 3 fixtures × 3 samples = **90 attempts**. Every attempt is scored and
published. No attempt was re-run, discarded, or chosen after the fact.

## 3. Scoring overview

Each attempt passes through four layers.

| Layer | What it measures | Nature | Weight |
|---|---|---|---|
| 1. Gate | The module plans as a root module with its own `minimal.tfvars` | Mechanical, pass/fail | Prerequisite for layer 2 |
| 2. Rubric and expertise | Fixture-specific consequences: security, data protection, audience fit, service expertise | Mechanical, itemized and weighted | 70% |
| 3. Judge | Design and craft against a published quality doctrine | LLM judge, calibrated against a human | 30% |
| 4. Statistics | Inputs, SLOC, tokens, time, estimated cost | Mechanical, descriptive | 0% (reported only) |

**Composite = 0.70 × mechanical + 0.30 × judge grade**, on a 0–100 scale.

## 4. Mechanical scoring

### 4.1 The gate

The runner keeps only the variables that have no default from the model's own
`minimal.tfvars`, then runs `tofu plan` on the module as a root module. A module that does
not plan **fails the gate**:

- its rubric and expertise scores are 0;
- it is still graded by the judge, which keeps its grade (see §6.3);
- the failure is flagged ✗ in every results table.

### 4.2 The rubric

Each fixture's `rubric.yaml` declares weighted items, checked by a declarative check engine
(`docs/generation-check-engine.md`). The engine never looks at variable names. It
evaluates outcomes in two places:

- **The plan.** Resources and attribute values in the defaults plan, and in the
  perturbation sweep described below.
- **The source.** Whether a value is a literal or flows from an input, traced through
  locals, `count`/`for_each`, dynamic blocks and `each.*`.

**The perturbation sweep.** For every documented input, the runner plans the module once
more with that one input changed: booleans flipped, and enumerated values from `contains()`
validations tried (up to five alternatives). The sweep reveals what an input actually
controls without the engine knowing what the model named it. A setting reached through a
direct toggle, a value inferred from an environment, or a derived local all score the same.
Collection-typed and free-string inputs are not perturbed.

Items take one of five **postures**, depending on what the item protects:

| Posture | Meaning | Passes when |
|---|---|---|
| Hardcoded | Security posture. Exposing it as an input is the defect, even if the default is safe. | Set to the secure value as a literal, unconditionally, and still secure in every sweep plan |
| On by default | Safe by default, with a legitimate reason to turn it off | On at defaults with a real way to turn it off. Always-on with no opt-out earns partial credit (0.75); off by default but reachable earns 0.5. |
| Offered | A capability the audience should be able to reach | Present at defaults or in at least one sweep plan |
| Graded | Better and worse mechanisms that both work | Credit for the best mechanism present |
| Budget | Interface size fits the audience | Full credit at or under the soft count, falling linearly to zero at the hard count |

Items are grouped by role:

- **H items:** core security, durability and operability.
- **A items:** audience fit, covering exposure, restraint and the budget.
- **B items:** baseline items applied to every fixture: provider version constraints and
  descriptions.

Two H items per fixture are **mandatory**: the most severe security failure modes. Failing
one is a **security finding** (⚠). It does not cap the score, but it marks the attempt
unshippable.

### 4.3 Expertise items

Each fixture also lists **expertise items**. These are service-specific touches an
experienced engineer adds without being asked, such as S3 bucket-owner-enforced ownership
or IAM database authentication on Cloud SQL. They are checked mechanically and pooled into
the mechanical score at weight 1 each, against rubric weights of 2–18. The rubric therefore
decides whether a module meets the bar, and expertise separates modules that do.

Expertise items come from observation. Candidates come from differences between models
and from the judge's rationales. Each is approved by the doctrine owner and records where
it came from. An item must not reward inventing requirements the brief never stated.

### 4.4 The mechanical score

    mechanical = (Σ rubric weight × credit + Σ expertise credit) / (Σ rubric weight + number of expertise items)

The rubric weight totals are 86 (G001), 97 (G002) and 72 (G003), including the baseline
items. Each fixture has 7–9 expertise items.

### 4.5 Validating the rubric: the reference matrix

Each fixture ships hand-written reference modules that the rubric must classify correctly:

- **Two good designs** must score at least 0.95:
  - `ref_lean` is opinionated, with few inputs and choices inferred from a concept such as
    environment.
  - `ref_flexible` is more configurable.
- **Several deliberately bad designs** must fail the specific items each was built to fail:
  - `bad_passthrough`: every setting is an input.
  - `bad_minimal`: a bare resource.
  - `bad_unsafe`: one critical setting is exposed as an input.
  - G003 also has `bad_open_slot`: a locked-down app with an open deployment slot.

The self-test runs this matrix against real cloud plans. If a deliberately good design
fails the rubric, the rubric is wrong. The matrix exists so that the rubric rewards outcomes
rather than one author's preferred shape.

## 5. The judge

### 5.1 What it grades

The judge is **Claude Opus 5.5**. It grades each module against the benchmark's quality
doctrine (`docs/good-opentofu.md`, edition `af3ae1dd9fdc1c0c`) on **14 sections**, scoring
each 0 (no credit), 1 (partial) or 2 (full):

- **Weight 3:** Sensitive values.
- **Weight 2:** Interface design, Variables and validation, Scope.
- **Weight 1:** Internal logic, Inline vs separate resources, Outputs, Iteration
  (`for_each` vs `count`), Data sources vs inputs, File layout, Lifecycle meta-arguments,
  Documentation, Deprecated and escape-hatch patterns, Anti-patterns.

The weighted mean is scaled to 0–100.

**The judge grades only what the rubric cannot.** The doctrine sections the rubric already
scores are given to the judge as context but are not graded: insecure configurations,
destructive defaults, unstated assumptions, tagging, versions, and provider declarations.
A defect therefore never costs a module in both components.

**Blind to authorship.** The judge sees the brief, the doctrine, and the module's files:
HCL first, then tfvars, then documentation. It never sees which model wrote the module.
The files are marked as untrusted data, so instructions inside a module are not followed.

**Sampling.** Each module is graded three times independently. Each section takes the
median of the three grades, and the judge returns one sentence of evidence per grade.

### 5.2 Calibration

A judge grade counts toward the composite only after the judge is calibrated against the
doctrine owner (the human who maintains the doctrine), fixture by fixture:

1. For one fixture, the judge grades 8 modules: 6 from models and the 2 references. The
   modules are shown under blind labels.
2. The doctrine owner records their own grade (0, 1 or 2) for every section of every
   module: 112 cells. They see the judge's grade and evidence beside each cell.
3. Agreement is the share of cells where the judge's grade exactly matches the human's,
   computed per section. The judge is calibrated only if **every section matches on at
   least 6 of 8 modules**. The gate is per section so that easy sections cannot carry a
   judge through hard ones.

A second judge (GPT-5.5) graded the same modules during calibration. The doctrine owner
reviewed in detail the cells where the two judges disagreed. Disagreements that came from
unclear doctrine wording led to the doctrine being reworded and both fixtures being graded
again. Final agreement for Claude Opus 5.5:

| Fixture | Cells | Exact agreement | Lowest section |
|---|---|---|---|
| G001 | 112 | 0.929 | 0.75 (Interface design, Scope, File layout, Documentation) |
| G002 | 112 | 0.973 | 0.875 (Interface design, File layout, Documentation) |
| G003 | 112 | 0.982 | 0.75 (Documentation) |

GPT-5.5 failed the gate on G001 (Interface design) and G003 (Documentation, Sensitive
values). A single judge is used across all fixtures, so that grades are comparable between
fixtures.

**The final modules.** The 2026-10 modules were graded with the same judge model, the same
judge code (unchanged since 2026-10-09), the same doctrine edition and the same sampling as
the calibration rounds. Calibration was carried over on that basis; the doctrine owner did
not re-review the final modules. Each grade file records where its calibration came from.

### 5.3 Known judge risks

- **Self-preference.** The judge and four of the ten candidates come from the same vendor.
  Blinding hides the author's name but not the author's style. An authorship test, which
  told the judge a fixed model had written every module, found no grade shift for the name.
  It does not rule out a preference for a familiar style. §7 shows the ranking with and
  without the judge.
- **Plan blindness.** The judge reads source and does not run `tofu plan`. It can miss a
  setting that the source omits and the provider defaults insecurely, and it can grade a
  module that does not plan. The rubric covers both cases. The two components are meant to
  complement each other.
- **Documentation accuracy is judged strictly.** Under the doctrine, any wrong or outdated
  statement earns 0 for Documentation, however small.

## 6. Aggregation and statistics

### 6.1 From attempts to scores

1. **Per attempt:** composite = 70 × mechanical + 0.30 × judge grade.
2. **Per model and fixture:** the median of the three attempts' composites, reported with
   the minimum–maximum range.
3. **Overall:** the mean of the three fixture medians, so each fixture counts equally.

Within a fixture the median is used, so one broken attempt out of three is reported as
one broken attempt instead of being averaged into a result that hides it.

### 6.2 Uncertainty

Three samples per cell is a small sample, so the overall score is reported with a
**bootstrap 95% confidence interval**:

- 10,000 resamples.
- Each model's three attempts per fixture are resampled with replacement, then the
  overall statistic is recomputed.

Each model also gets a **rank interval**: the 2.5th to 97.5th percentile of its rank across
joint bootstrap draws, following the LMArena convention. A ranking claim is made only where
intervals separate. Pairwise win probabilities are published in the data release.

With n = 3, the bootstrap is coarse, and intervals are wide for models with one outlier
attempt. Read them as a statement of how far the data supports a ranking, not as precise
coverage.

### 6.3 Gate failures and findings

A module that fails the gate keeps its judge grade, so its composite is about 25–30 rather
than 0. It is flagged ✗ and counted in the results tables. The judge grade is kept because
the judge grades design and craft, which a plan failure does not erase. The flag shows that
the attempt was unshippable. Security findings are handled the same way: flagged ⚠ and
counted, but no score cap.

### 6.4 Cost and run statistics

Estimated cost per attempt uses list prices from OpenRouter, dated 2026-10-23, for every
model, including closed models routed through their own APIs. Cache reads are charged at
0.1× and cache writes at 1.25× the input price. Judge calls are excluded. Token counts,
wall-clock time, SLOC and input counts come from the eval logs. None of them affects any
score.

## 7. Errata and re-scoring

Two scorer defects were found during the per-model analysis, before publication, and fixed.
Both affected one attempt each.

- **HCL reserved words as object keys.** The static parser rejected `{ in = …, out = … }`,
  which is valid HCL. It dropped the whole file without reporting it, which blinded every
  static check on that file. The attempt affected was GPT-6 Astra, G003, sample 1, which had
  been recorded as a false security finding.
- **Built-in provider.** The provider-constraint item (B1) required OpenTofu's built-in
  `terraform` provider, used by `terraform_data`, to be declared in `required_providers`,
  where it cannot be declared. The attempt affected was Claude Fable 5.1, G003, sample 1.

Both fixes are in engine commit `6581141` and are covered by the G003 reference matrix. Both
affected attempts (and the other attempts in their eval logs) were re-scored from the stored
modules. Nothing was regenerated, and the original logs are published alongside the
corrected ones.

## 8. Limitations

- **Plan-only.** Nothing is applied. Errors that only appear at apply time, idempotency,
  and destroy behavior are not measured.
- **Three services.** One service per cloud does not represent the breadth of infrastructure
  work, and results should not be generalized beyond these fixtures.
- **Small samples.** Three attempts per model and fixture. Neighboring models in the
  results frequently cannot be told apart, and the tables say so.
- **One scaffold.** Scores measure a model inside this scaffold and prompt. A different agent
  scaffold could produce different results.
- **Sweep coverage.** The sweep changes one input at a time and does not perturb
  collections or free-form strings. A capability reachable only by supplying a resource ID
  (for example, an existing log workspace), or by setting a list, can go undetected. A
  defect that appears only when a collection input is populated (for example, a databases
  input that breaks the plan once used) is not caught by the rubric. The judge sometimes
  catches it.
- **Public fixtures.** Briefs, rubrics, references and the doctrine are public and may enter
  future training data. Rising scores on these fixtures without corroboration from held-out
  variants should be read as contamination.
- **Opinionated doctrine.** The judged 30% encodes one organization's documented
  preferences. Per-section grades are published so a reader can discard any section they
  disagree with, and the mechanical score is reported on its own.

## 9. Disclosure

iac-bench is developed by Massdriver, which builds infrastructure tooling. Massdriver wrote
the briefs, rubrics, references and doctrine, and its staff acted as the calibrating human.

## 10. Reproducibility and data

The repository contains everything needed to reproduce or audit a score:

- **Evaluation code:** `src/iacbench/`.
- **Prompt:** `prompts/generate-module.md`.
- **Fixtures, rubrics and references:** `fixtures/` and `testdata/`.
- **Doctrine:** `docs/good-opentofu.md`.
- **Scoring policy:** `composite-scoring-policy.yaml`.
- **Price snapshot:** `prices.yaml`.

The 2026-10 data release contains:

- all 90 eval logs, including transcripts, and the original logs that were superseded;
- the 90 generated modules;
- the judge's grades and evidence for every module and section;
- the calibration review sheets and the human grades;
- the computed statistics.

Results are licensed under CC BY 4.0.

To reproduce one cell:

```bash
uv run inspect eval src/iacbench/task.py@generate_module -T fixture=G002 \
    --model anthropic/claude-sonnet-5-5 --epochs 3
uv run iacbench judge --grade --samples 3 --fixture G002 \
    --candidates <collected modules> --model anthropic/claude-opus-5-5
```

## Changelog

- **2026-10 (this release).** First public release. Three generation fixtures, ten models,
  three samples each. Scores are not comparable with any earlier internal run: briefs,
  rubrics and the doctrine were revised during development, and every revision invalidates
  earlier results for the affected fixture.

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
