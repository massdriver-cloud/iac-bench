# Contributing to iacbench

Thanks for your interest. This project holds itself to a strict reproducibility
standard: **every verdict must be mechanically reproducible or explicitly
disclosed as judged**, and every scoring component must be validated against
known answers before it counts. Contributions are expected to preserve that.

## Development setup

Open the repo in the dev container (`.devcontainer/`) — it provides pinned
OpenTofu, `uv`, and the Python environment (`uv sync` runs automatically).
All commands below run inside the container.

```bash
uv run iacbench selftest          # validate all checkers against known answers
uv run iacbench render --fixture F001 --seed 42 --out /tmp/f
uv run inspect eval src/iacbench/task.py -T fixture=F001 --model mockllm/model
```

Tier-2 fixtures (real AWS, creating resources) require AWS credentials and
`IACBENCH_AWS=1`. Generation scoring (plan-only) requires `IACBENCH_CLOUD=1` plus
credentials for the cloud each fixture's rubric declares; fixtures whose cloud has no
credentials in the environment are skipped. CI runs only the hermetic tier.

## Contributing a fixture

A fixture PR is accepted only when it ships **complete with its evidence**:

1. **The fixture** (`fixtures/<domain>/<ID>/`): manifest/rubric, templates or
   brief. Briefs for generation fixtures are short, realistic human prompts —
   scored criteria are hidden and must never leak into the brief or scaffold
   prompts.
2. **Its known-answer matrix** (`testdata/solutions/<ID>/`): at least two
   *structurally different* correct/good solutions (this is what proves the
   checkers accept more than one valid answer), the broken/naive baseline, and
   cheat variants targeting each anti-gaming invariant, with `expectations.yaml`.
3. **A green selftest**: `uv run iacbench selftest --fixture <ID>` must pass.
   A fixture whose checkers haven't been validated against known answers does
   not merge.
4. **Provenance and licensing**: document the fixture's source and the license
   of any incorporated dataset/code, and enough method description to reproduce
   expected behavior independently. Do not include credentials, real
   infrastructure identifiers, or non-redistributable content.

## Changing scorers, checkers, prompts, or the quality doctrine

Scoring changes rewrite history (stored results are re-scorable by design), so:

- Any change to a checker, scorer, probe, judge prompt, or `good-opentofu.md`
  must state the **expected score movement** and why it is correct.
- The full selftest must pass; add or update known-answer solutions when the
  change alters what "correct" means.
- Re-score stored model output with `iacbench rescore` and account for every
  difference it prints against the logged scores.
- Judge-affecting changes (prompts, doctrine, judge model) create a new hashed
  edition; substantial changes require re-checking calibration against the
  human-ranked set before the judged column is trusted.
- Weights and composite formulas change only via `composite-scoring-policy.yaml` /
  `rubric.yaml` version bumps — never silently.

## Ground rules

- **No credentials anywhere** — fixtures, tests, logs, and examples must be
  credential-free and deterministic. Hermetic fixtures may not require cloud
  access; Tier-2 fixtures must tag all resources `iacbench=true` and destroy
  them after scoring.
- **Mechanical before judged** — if a criterion can be checked from `tofu`
  output, plan JSON, or static analysis, it belongs in the rubric, not the
  judge. Judged scores stay in their own column, never folded into mechanical
  ones.
- **Scores are true values** — never cap or fudge a score to express severity;
  security failures are recorded as findings and fail verdicts instead.

## Before opening a PR

```bash
uv run ruff check src
uv run iacbench selftest
```

By contributing, you agree that your contribution is licensed under the
repository's Apache-2.0 license.
