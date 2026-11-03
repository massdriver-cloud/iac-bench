# iac-bench 2026-10 data release

Every artifact behind the iac-bench 2026-10 results: ten models, three generation fixtures,
three attempts each (90 attempts). It holds each attempt's full transcript, the OpenTofu
module it produced, its mechanical score, the judge's grades with evidence, and the human
calibration of the judge.

## Provenance

| | |
|---|---|
| Engine | commit [`0ecceed`](https://github.com/massdriver-cloud/iac-bench/commit/0ecceed) |
| Fixtures and rubric editions | G001 (AWS S3) `7159cedae642d9e7`, G002 (GCP Cloud SQL) `36ff21d5fa87ec1a`, G003 (Azure App Service) `59f6dcc6fd047fcf` |
| Doctrine edition | `af3ae1dd9fdc1c0c` (`docs/good-opentofu.md`) |
| Judge | `anthropic/claude-opus-5-5`, absolute grading, 3 samples per module |
| Calibration | carried from rounds G001-r9, G002-r3 and G003-r1 (`calibration/`) |
| OpenTofu | 1.12.5 |
| Runs | 2026-10-22; judged 2026-10-23 |
| Prices | OpenRouter list prices dated 2026-10-23 (`prices.yaml` at the engine commit) |

Models: `anthropic/claude-fable-5-1`, `anthropic/claude-haiku-5-5`,
`anthropic/claude-opus-5-5`, `anthropic/claude-sonnet-5-5`, `google/gemini-3.1-pro-preview`,
`google/gemini-3.6-flash`, `openai/gpt-6-astra`, `openai/gpt-6-luna`,
`openrouter/deepseek/deepseek-v4-pro-0813`, `openrouter/moonshotai/kimi-k3`.

## Layout

| Path | Contents |
|---|---|
| `attempts.csv` | One row per attempt: gate, security findings, rubric, mechanical, judge and composite scores, interface size, tokens, time, estimated cost. `module_sha` joins every other file. |
| `items.csv` | Every rubric and expertise item of every attempt. |
| `judge_sections.csv` | The judge's grade (0, 1 or 2) for each doctrine section of each attempt, with its evidence as a JSON list. |
| `logs/` | The 30 Inspect eval logs (`.eval`): transcripts, tool calls, plan output and score metadata. |
| `logs/superseded/` | The two original logs replaced when two scorer defects were fixed before publication (Methodology §7). |
| `candidates/<fixture>/<model>-e<n>/` | The 90 modules exactly as each model left them. |
| `judge/<fixture>-opus-5-5/grades.json` | Final judge grades, per-sample section scores and evidence. |
| `calibration/<round>/review/` | The blind review sheets and the doctrine owner's grades (`review.yaml`, `blind-key.yaml`). |
| `calibration/<round>/judge-*/` | Both judges' grades of the calibration modules (Claude Opus 5.5 and GPT-5.5). |
| `analysis/stats.json` | Bootstrap confidence intervals, rank intervals and pairwise win probabilities. |
| `analysis/datapack/` | Per-model summaries the published tables are built from. |
| `redactions.json` | Every redacted file, and the module hash remapped by redaction. |

## Redactions

The sandbox cloud accounts' identifiers are replaced wherever they appear: the AWS account
ID with `123456789012`, the GCP project ID with `iacbench-sandbox`, and the Azure
subscription ID with `00000000-0000-0000-0000-000000000000`. They came from `tofu plan`
output in transcripts and from one model-written example file. Nothing else is changed:
every log reads back identical to its original apart from these strings, and scores, grades
and hashes are as recorded. Redacting the example file changed that module's content hash;
`redactions.json` maps it to the hash its score was recorded under.

## Using the data

Read any transcript in Inspect's log viewer:

```bash
uv run inspect view --log-dir results/2026-10/logs
```

Rebuild the published report tables with the engine that produced them:

```bash
git worktree add ../iac-bench-0ecceed 0ecceed
cd ../iac-bench-0ecceed && uv sync
uv run iacbench report --log-dir ../iac-bench/results/2026-10/logs \
    --judge-dir ../iac-bench/results/2026-10/judge/G001-opus-5-5 \
    --judge-dir ../iac-bench/results/2026-10/judge/G002-opus-5-5 \
    --judge-dir ../iac-bench/results/2026-10/judge/G003-opus-5-5
```

Re-score the modules with an engine and compare every item with the recorded scores
(plans run against each fixture's cloud):

```bash
uv run iacbench rescore --fixture G003 --candidates results/2026-10/candidates/G003 \
    --log-dir results/2026-10/logs --redactions results/2026-10/redactions.json
```

## License

The data is licensed under [CC BY 4.0](LICENSE). The code that produced it is licensed
under Apache-2.0 (the repository's `LICENSE`).
