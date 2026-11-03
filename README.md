# iacbench

A benchmark that scores LLMs on OpenTofu infrastructure-as-code tasks. Built on
[Inspect AI](https://inspect.aisi.org.uk/) for the agent scaffold, model adapters, and
transcript logging; the fixtures and mechanical checkers are this repo's own.

**Design principle:** the majority of every score is mechanical. Pass/fail verdicts and
the rubric come from running `tofu` and inspecting its output (exit codes, plan JSON,
parsed HCL) — never from comparing against a stored correct answer. A separate, smaller
judged component grades candidates against our published definition of module quality
(`docs/good-opentofu.md`) — our documented preferences, human-gated (it enters the
composite only after clearing calibration against human rankings) and reported per
doctrine section, so a reader who rejects any preference can discount exactly that row —
or ignore the judged layer entirely and use the mechanical columns alone.

## Current scope

Two tiers, end to end:

- **Tier 1 — `plan_failure`** (F001–F003): hermetic fixtures using credential-free providers
  (`null`, `random`, `terraform_data`). Zero cost, fully reproducible. Note: current models
  saturate these (measured 31/31); they now serve as harness smoke tests.
- **Tier 2 — `apply_failure`** (F101+): real AWS resources in a sandbox account. The fixture
  applies partway, fails, and the model must fix the config and converge it. Everything is
  tagged `iacbench=true`, every scored attempt ends in `tofu destroy`, and `iacbench sweep`
  finds/removes leaks.
- **Tier 2 — `generation`** (G001+): the model builds a standalone root module from a
  use-case brief (shipping a `minimal.tfvars` for its required variables) and is scored
  against a weighted, brief-specific rubric — plan-only, no resources created. The module
  is evaluated **at its own defaults**, never through the model's example input choices:
  security items require hardcoded-secure source, behavioral items pass if reachable
  through the documented interface. Checks are declared in each fixture's `rubric.yaml`
  and evaluated by a service-agnostic verb engine — adding a fixture requires no Python.
  See `docs/generation-check-engine.md` for the evidence model and verb vocabulary, and
  `docs/generation-eval-design.md` for the layered scoring model (functional gate →
  semantic rubric → judged layer → unweighted descriptive stats) and why generic metrics
  like "% of variables validated" are deliberately never scored.

## Layout

```
fixtures/<domain>/<ID>/       fixture.yaml + Jinja2 template (seeded rendering)
testdata/solutions/<ID>/      known-answer solutions for selftest (correct, alt, cheats)
prompts/                      versioned prompt templates
src/iacbench/                 renderer, tofu wrapper, invariant checkers, Inspect task
runs/, logs/                  output; gitignored
```

## Getting started

Open the repo in the dev container. It installs the latest OpenTofu, Go and uv, runs `uv sync`, and
builds `tools/hclast`, the Go helper the static lens uses to parse HCL with HashiCorp's library.
The engine refuses a helper older than its source; rebuild it with `make -C tools/hclast`.

Then:

```bash
# validate the checkers against the known-answer solution matrix — run this first
uv run iacbench selftest

# unit-test the static analysis (solver, value proofs) without cloud credentials
uv run pytest tests

# render a fixture to look at it
uv run iacbench render --fixture F001 --seed 42 --out /tmp/f001

# smoke-test the eval plumbing without a real model
uv run inspect eval src/iacbench/task.py -T fixture=F001 --model mockllm/model

# real eval: one fixture, 3 seeds, 5 repeats each
uv run inspect eval src/iacbench/task.py -T fixture=F001 -T seeds=0,1,2 \
    --model anthropic/claude-sonnet-5 --epochs 5

# browse transcripts and scores
uv run inspect view

# markdown report: Wilson intervals (fix domains), generation rubric scores,
# expertise differential tables, run statistics (duration/tokens/estimated cost
# from prices.yaml/SLOC), and judged rankings
uv run iacbench report --log-dir logs --judge-dir runs/judge/G001-v1 --out report.md
```

### Tier 2 (real AWS)

Tier-2 commands need cloud credentials in the environment (they are not baked into the
container). Generation fixtures plan against AWS, GCP, or Azure — each rubric declares
which — and only ever plan, so read-only credentials suffice and are recommended.
`scripts/cloud-env` prints short-lived credentials for all three clouds on the host, for
piping into the container. With creds present:

```bash
# validate the Tier-2 checkers — creates and destroys real (free-tier) resources
IACBENCH_AWS=1 AWS_REGION=us-east-1 uv run iacbench selftest --fixture F101

# real eval against the apply-failure task
uv run inspect eval src/iacbench/task.py@fix_apply_failure -T fixture=F101 \
    --model anthropic/claude-sonnet-5 --epochs 5

# leak backstop: list (exit non-zero if anything found) or delete tagged leftovers
uv run iacbench sweep
uv run iacbench sweep --delete

# generation: model builds a module from fixtures/generation/G001/brief.md
uv run inspect eval src/iacbench/task.py@generate_module -T fixture=G001 \
    --model anthropic/claude-sonnet-5 --epochs 3

# generation selftest: scores each fixture's reference matrix (2 good designs,
# 3 bad) — plan-only, against the cloud the fixture's rubric declares
IACBENCH_CLOUD=1 AWS_REGION=us-east-1 uv run iacbench selftest --fixture G001

# judge layer: absolute grades, experimental until calibrated against human verdicts
uv run iacbench judge --fixture G001 --candidates runs/candidates/G001 --grade \
    --model openai/gpt-5.5 --out runs/judge/G001-gpt
uv run iacbench calibrate sheets --fixture G001 --candidates runs/candidates/G001 \
    --judge-dir runs/judge/G001-gpt --judge-dir runs/judge/G001-opus --out runs/calibration/G001
# ...fill runs/calibration/G001/review.yaml (your grade per module and section), then:
uv run iacbench calibrate finalize --judge-dir runs/judge/G001-gpt --judge-dir runs/judge/G001-opus \
    --out runs/calibration/G001
```

Tier-2 scoring (invariants A1–A6): validate, re-apply exits zero, required addresses in
state, no expected resources removed, no forbidden edits, and an **empty refresh plan after
apply** — the provider's own read of real infrastructure is the existence assertion, so no
per-fixture cloud assertions are needed. Cleanup (`tofu destroy`) always runs after scoring
and its outcome is recorded as `destroy_clean`.

## Scoring: the five invariants

Computed in `src/iacbench/checkers.py`, all five always evaluated:

| | Check | Defeats |
|--|-------|---------|
| I1 | `tofu validate` exits zero | |
| I2 | `tofu plan` exits zero | |
| I3 | required addresses present in plan JSON | deleting the offending resource |
| I4 | no originally-declared resource missing; count ≥ minimum | commenting out / emptying files |
| I5 | no forbidden file edited (lockfile, version pins); no blocked write attempts | fixing the symptom by editing harness files |

Verdict is `pass` only when all five hold. Efficiency metrics (diff size, tofu invocations)
are recorded in score metadata but never folded into the verdict.

## Adding a fixture

1. Create `fixtures/<domain>/<ID>/fixture.yaml` (see F001 for the schema: `error_class`,
   `error_pattern`, `seed_params`, `required_addresses`, `forbidden_file_edits`,
   `min_resource_count`) and a `template/` dir. Files ending `.j2` are rendered with Jinja2
   against the seed context; everything else is copied verbatim. Seed mapping is mixed-radix:
   seed 0 always picks the first value of every `seed_params` list.
2. Create `testdata/solutions/<ID>/` with `expectations.yaml` and the solution matrix:
   `correct/`, `correct_alt/` (a *structurally different* valid fix — this is what proves the
   checkers aren't answer-key matching), `unfixed/`, and the cheat variants. Solutions are
   authored against seed 0.
3. Run `uv run iacbench selftest --fixture <ID>` until green. Selftest also asserts the
   fixture is genuinely broken at multiple seeds with the declared error pattern, and that
   rendering is deterministic.

## Adding a model

No adapter code needed — Inspect AI provides the providers. Pass `--model
<provider>/<model-id>` (e.g. `anthropic/...`, `openai/...`, `google/...`,
`bedrock/...`) with the matching API key env var. See the Inspect docs for the full list.

## Benchmark integrity

Operating rules — no retractions, no private variants, identical treatment,
pinned model identifiers, scoring provenance, and what this benchmark does
not measure — are published in `docs/governance.md`.

- **Contamination stance (v0.1):** all current fixtures, briefs, and reference
  solutions are public in this repository, which means future models may train
  on them. Scores on public fixtures should be read accordingly. The record
  schema carries a `visibility: public | heldout` field from day one; starting
  with the next fixture release, each public fixture will be paired with
  held-out variants whose scores validate the public set. Rising public-fixture
  scores that held-out variants don't corroborate indicate contamination, not
  capability.
- **Judged scores are disclosed, gated, and separable.** The judge model, its
  prompt, and the quality-doctrine document are hashed into every judgment.
  The report folds a judge grade into the composite only when its stored
  calibration status says it cleared the human-agreement gate — otherwise the
  composite is computed from the mechanical components alone and the grade is
  shown flagged experimental. Grades are also reported per doctrine section,
  and mechanical columns never depend on the judge.
- **Scores are true values.** Security failures never cap scores — they are
  reported as findings, flagged on scored rows, and fail the pass/fail verdict.
- **Cost claims are versioned.** Estimated costs derive from `prices.yaml`, a
  dated pricing snapshot printed with every report.

## License and contributing

Apache-2.0 (see `LICENSE`). Contributions welcome — see `CONTRIBUTING.md` for
the fixture contract (reference matrix + selftest required) and scoring-change
rules, and `SECURITY.md` for private vulnerability reporting.

## Scaffold contract (v1)

The model gets exactly these tools: `list_files`, `read_file`, `write_file` (whole-file,
confined to the scratch dir, forbidden paths rejected and recorded), `tofu_validate`,
`tofu_plan` (accepts an optional `var_file`), `tofu_fmt`, `submit`. No arbitrary shell.
`tofu init` is run by the harness. Limits: wall clock per attempt is task-specific
(600s plan-fix, 900s apply-fix, 1800s generation), 120s per tofu invocation, tool
output truncated at 8 KB. Changing any of this invalidates comparisons
with earlier runs — versioned as `SCAFFOLD_CONTRACT_VERSION` in `src/iacbench/__init__.py`,
pinned at "1" until the benchmark is published (pre-launch changes simply invalidate old
runs; see the versioning stance in `docs/generation-check-engine.md`).
