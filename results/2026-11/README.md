# iac-bench 2026-11 data release

Every artifact behind the iac-bench 2026-11 results: twenty-four models, six generation
fixtures, three attempts each (432 attempts). It holds each attempt's full transcript, the
OpenTofu module it produced, its mechanical score, the judge's grades with evidence, and the
human calibration of the judge.

## Provenance

| | |
|---|---|
| Code | tag [`2026-11.1`](https://github.com/massdriver-cloud/iac-bench/tree/2026-11.1) |
| Fixtures and rubric editions | G001 (AWS S3) `4859493b9141ffb0`, G002 (GCP Cloud SQL) `7d6a5c8f51435fb7`, G003 (Azure App Service) `8fb13a648f9e7ee7`, G004 (AWS Aurora global database) `c7ea5fd9934196c7`, G005 (GCP GKE Standard) `02a5c65516f2bc51`, G006 (Azure storage account) `cd75468426b2ebee` |
| Doctrine edition | `af3ae1dd9fdc1c0c` (`docs/good-opentofu.md`) |
| Judge | `anthropic/claude-opus-5-5`, absolute grading, 3 samples per module |
| Calibration | against the doctrine owner's grades on G001–G003 (`calibration/`); G004–G006 carry the pooled G001–G003 calibration |
| OpenTofu | 1.12.5 |
| Limits | 300 messages and 3600 seconds per attempt |
| Runs | G004–G006 and the eight new models on G001–G003: 2026-11-23 and 2026-11-24, judged 2026-11-24. The G001–G003 attempts of the sixteen 2026-10 models are the 2026-10 attempts (2026-10-22 and 2026-11-10), rescored under the current rubrics, except GLM-5.3 on G002 and G003, Kimi K3 on G003 and Gemini 3.6 Flash on G003, run again on 2026-11-23 under the current limits. Version 2026-11.1 replaces Gemini 3.8 Flash's G002 attempts, which ran on 2026-11-24 without GCP credentials in the environment, with a run on 2026-11-25 |
| Scoring | every attempt scored with the code at tag `2026-11.1`, recorded in the logs as engine commit `df5e4f2` (the same code before merge) |
| Archive | Zenodo, [doi:10.5281/zenodo.24540782](https://doi.org/10.5281/zenodo.24540782) |
| Prices | OpenRouter list prices on each model's run date (`prices.yaml`) |

Models: `anthropic/claude-fable-5-1`, `anthropic/claude-fable-5-2`, `anthropic/claude-haiku-5-5`, `anthropic/claude-opus-5-5`, `anthropic/claude-sonnet-5-5`, `google/gemini-3.1-pro-preview`, `google/gemini-3.6-flash`, `google/gemini-3.8-flash`, `google/gemini-4-argon`, `google/gemini-4-carbon`, `google/gemini-4-hydrogen`, `google/gemini-4-neon`, `openai/gpt-6-astra`, `openai/gpt-6-luna`, `openai/gpt-6.1-sol`, `openai/gpt-6.1-terra`, `openai/gpt-6.2-astra`, `openai/gpt-6.2-sol`, `openrouter/deepseek/deepseek-v4-pro-0813`, `openrouter/moonshotai/kimi-k3`, `openrouter/moonshotai/kimi-k3.1-pro`, `openrouter/qwen/qwen3.8-2.4t-a95b`, `openrouter/qwen/qwen4-max` and `openrouter/z-ai/glm-5.3`. The pinned OpenRouter endpoints (Kimi K3.1 Pro on Moonshot AI, GLM-5.3 on
Z.ai, Qwen3.8 2.4T-A95B and Qwen4 Max on Alibaba) ran with fallbacks disabled.

## Layout

| Path | Contents |
|---|---|
| `attempts.csv` | One row per attempt: gate, security findings, rubric, mechanical, judge and composite scores, known apply failures, failed penalty items, interface size, tokens, time, estimated cost. `module_sha` joins every other file. |
| `items.csv` | Every rubric and expertise item of every attempt. |
| `judge_sections.csv` | The judge's grade (0, 1 or 2) for each doctrine section of each attempt, with its evidence as a JSON list. |
| `logs/` | The 144 Inspect eval logs (`.eval`): transcripts, tool calls, plan output and score metadata. |
| `candidates/<fixture>/<model>-e<n>/` | The 432 modules exactly as each model left them. |
| `judge/<fixture>-opus-5-5/grades.json` | Final judge grades, per-sample section scores and evidence, and the calibration each fixture carries. |
| `calibration/<fixture>/review/` | The blind review sheets and the doctrine owner's grades (`review.yaml`, `blind-key.yaml`). |
| `calibration/<fixture>/judge-*/` | Both judges' grades of the calibration modules (Claude Opus 5.5 and GPT-5.5). |
| `analysis/stats.json` | Bootstrap confidence intervals, rank intervals and pairwise win probabilities. |
| `analysis/datapack/` | Per-model summaries the published tables are built from. |
| `redactions.json` | Every redacted file, and the module hashes remapped by redaction. |

## Redactions

The sandbox cloud accounts' identifiers are replaced wherever they appear: the AWS account
ID with `123456789012`, the GCP project ID with `iacbench-sandbox` and its project number
with `000000000000`, the Azure subscription ID with `00000000-0000-0000-0000-000000000000`,
the Azure tenant ID with `11111111-1111-1111-1111-111111111111` and the Azure client ID
with `22222222-2222-2222-2222-222222222222`. Credentials are replaced with `<redacted>`, and a model client's notice about its own
configuration is removed from the log records. Scores, grades
and module hashes are as recorded. Redacting a model-written variable file changes its
module's content hash; `redactions.json` maps each such module to the hash its score was
recorded under.

## Using the data

Read any transcript in Inspect's log viewer:

```bash
uv run inspect view --log-dir results/2026-11/logs
```

Rebuild the published report tables:

```bash
uv run iacbench report --log-dir results/2026-11/logs \
    --judge-dir results/2026-11/judge/G001-opus-5-5 \
    --judge-dir results/2026-11/judge/G002-opus-5-5 \
    --judge-dir results/2026-11/judge/G003-opus-5-5 \
    --judge-dir results/2026-11/judge/G004-opus-5-5 \
    --judge-dir results/2026-11/judge/G005-opus-5-5 \
    --judge-dir results/2026-11/judge/G006-opus-5-5
```

Re-score the modules and compare every item with the recorded scores (plans run against
each fixture's cloud):

```bash
uv run iacbench rescore --fixture G004 --candidates results/2026-11/candidates/G004 \
    --log-dir results/2026-11/logs --redactions results/2026-11/redactions.json
```

## License

The data is licensed under CC BY 4.0 (`LICENSE`). The code that produced it is Apache-2.0.
