# iacbench

A benchmark that scores how well LLMs write reusable OpenTofu modules. Built on
[Inspect AI](https://inspect.aisi.org.uk/) for the agent scaffold, model adapters, and
transcript logging; the fixtures and scoring are this repo's own.

**Design principle:** the majority of every score is mechanical. The rubric comes from
running `tofu` and inspecting its output (exit codes, plan JSON, parsed HCL), never from
comparing against a stored correct answer. A separate, smaller judged component grades
modules against our published definition of module quality (`docs/good-opentofu.md`):
our documented preferences, human-gated (it enters the composite only after clearing
calibration against human grades) and reported per doctrine section, so a reader who
rejects any preference can discount exactly that row, or ignore the judged layer entirely
and use the mechanical columns alone.

## What it measures

Each fixture is a short brief for one cloud service and one audience: an S3 bucket for
application teams (G001, AWS), a Cloud SQL for PostgreSQL instance for a DBA team (G002,
GCP), an App Service web app for an SRE team (G003, Azure). The model builds a standalone
root module from the brief, shipping a `minimal.tfvars` for its required variables, and is
scored against a weighted, brief-specific rubric, plan-only, with no resources created.

The module is evaluated **at its own defaults**, never through the model's example input
choices: security items require source that no input can weaken, and behavioral items pass
if reachable through the documented interface. Checks are declared in each fixture's
`rubric.yaml` and evaluated by a service-agnostic verb engine; adding a fixture requires no
Python. See `docs/generation-check-engine.md` for the evidence model and verb vocabulary,
and `docs/generation-eval-design.md` for the layered scoring model (functional gate →
semantic rubric → judged layer → unweighted descriptive stats) and why generic metrics
like "% of variables validated" are deliberately never scored.

## Layout

```
fixtures/generation/<ID>/     brief.md + rubric.yaml (baseline.yaml applies to every fixture)
testdata/solutions/<ID>/      reference matrix for selftest: good designs and targeted bad ones
prompts/                      versioned prompt templates (generation, judge)
src/iacbench/                 Inspect task, check engine, solver, judge, report
tools/hclast/                 Go helper: parses HCL with HashiCorp's library
results/<release>/            published data releases: logs, modules, grades, calibration (see each README)
runs/, logs/                  output; gitignored
```

## Getting started

Open the repo in the dev container. It installs the latest OpenTofu, Go and uv, runs `uv sync`, and
builds `tools/hclast`, the Go helper the static lens uses to parse HCL with HashiCorp's library.
The engine refuses a helper built from a different source; rebuild it with `make -C tools/hclast`.

Scoring plans against real clouds, so it needs credentials in the environment (they are not
baked into the container). Each fixture's rubric declares its cloud, and scoring only ever
plans, so read-only credentials suffice and are recommended. `scripts/cloud-env` prints
short-lived credentials for all three clouds on the host, for piping into the container.

```bash
# unit-test the static analysis (solver, value proofs) without cloud credentials
uv run pytest tests

# validate the rubric checks against each fixture's reference matrix (plan-only)
IACBENCH_CLOUD=1 AWS_REGION=us-east-1 uv run iacbench selftest --fixture G001

# real eval: the model builds a module from fixtures/generation/G001/brief.md
uv run inspect eval src/iacbench/task.py@generate_module -T fixture=G001 \
    --model anthropic/claude-sonnet-5 --epochs 3

# browse transcripts and scores
uv run inspect view

# markdown report: composite leaderboard, rubric and expertise tables, judged grades by
# doctrine section, run statistics (duration, tokens, estimated cost from prices.yaml, SLOC)
uv run iacbench report --log-dir logs --judge-dir runs/judge/G001-opus --out report.md

# after an engine change: re-score stored candidates, compare with their logged scores
uv run iacbench rescore --fixture G001 --candidates runs/candidates/G001 --log-dir logs

# judge layer: absolute grades, experimental until calibrated against human grades
uv run iacbench judge --fixture G001 --candidates runs/candidates/G001 --grade \
    --model anthropic/claude-opus-5-5 --out runs/judge/G001-opus
uv run iacbench calibrate sheets --fixture G001 --candidates runs/candidates/G001 \
    --judge-dir runs/judge/G001-opus --out runs/calibration/G001
# ...fill runs/calibration/G001/review.yaml (your grade per module and section), then:
uv run iacbench calibrate finalize --judge-dir runs/judge/G001-opus --out runs/calibration/G001
```

## Adding a fixture

1. Create `fixtures/generation/<ID>/` with `brief.md` (the request the model sees) and
   `rubric.yaml` (weighted items declared as checks; see `docs/generation-check-engine.md`).
2. Create `testdata/solutions/<ID>/` with `expectations.yaml` and the reference matrix:
   intentionally different good designs and bad ones that each fail specific items. The
   good references must pass every mandatory item and outscore every bad one.
3. Run `IACBENCH_CLOUD=1 uv run iacbench selftest --fixture <ID>` until green.

## Adding a model

No adapter code needed: Inspect AI provides the providers. Pass `--model
<provider>/<model-id>` (e.g. `anthropic/...`, `openai/...`, `google/...`,
`openrouter/...`) with the matching API key env var. See the Inspect docs for the full list.

## Benchmark integrity

Operating rules (no retractions, no private variants, identical treatment,
pinned model identifiers, scoring provenance, and what this benchmark does
not measure) are published in `docs/governance.md`.

- **Contamination stance:** all current fixtures, briefs, and reference
  solutions are public in this repository, which means future models may train
  on them. Scores on public fixtures should be read accordingly. The record
  schema carries a `visibility: public | heldout` field; each public fixture
  will be paired with held-out variants whose scores validate the public set.
  Rising public-fixture scores that held-out variants don't corroborate
  indicate contamination, not capability.
- **Judged scores are disclosed, gated, and separable.** The judge model, its
  prompt, and the quality-doctrine document are hashed into every judgment.
  The report folds a judge grade into the composite only when its stored
  calibration status says it cleared the human-agreement gate; otherwise the
  composite is computed from the mechanical components alone and the grade is
  shown flagged experimental. Grades are also reported per doctrine section,
  and mechanical columns never depend on the judge.
- **Scores are true values.** Security failures never cap scores: they are
  reported as findings, flagged on scored rows, and fail the pass/fail verdict.
- **Cost claims are versioned.** Estimated costs derive from `prices.yaml`, a
  dated pricing snapshot printed with every report.

## License and contributing

Code is Apache-2.0 (see `LICENSE`); each data release under `results/` carries its own
license. To cite iac-bench or a release, use `CITATION.cff` (GitHub's "Cite this repository").
Contributions welcome: see `CONTRIBUTING.md` for the fixture contract (reference
matrix + selftest required) and scoring-change rules, and `SECURITY.md` for private
vulnerability reporting.

## Scaffold contract (v1)

The model gets exactly these tools: `list_files`, `read_file`, `write_file` (whole-file,
confined to the working directory), `tofu_validate`, `tofu_plan` (accepts an optional
`var_file`), `tofu_fmt`, `submit`. No arbitrary shell. `tofu init` is run by the harness.
Limits: 1800s wall clock and 150 messages per attempt, 120s per tofu invocation, tool
output truncated at 8 KB. Any change to the contract is versioned as
`SCAFFOLD_CONTRACT_VERSION` in `src/iacbench/__init__.py` and invalidates comparisons
with runs under another version.
