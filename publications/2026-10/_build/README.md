# Building the 2026-10 publication

The article prose lives in `../_templates/`. Every number, table and code excerpt is
generated from the run data by these scripts. Run them from the repository root, in this
order, inside the dev container:

| Step | Command | Produces |
|---|---|---|
| 1 | `uv run python publications/2026-10/_build/collect_final.py` | `runs/final/candidates/`, `runs/final/scores.json`, from `logs/final/` |
| 2 | `uv run python publications/2026-10/_build/datapack.py` | `runs/final/datapack/`: per-model scores, items, judge sections and evidence |
| 3 | `uv run python publications/2026-10/_build/stats.py` | `runs/final/stats.json`: bootstrap CIs, rank intervals, win probabilities |
| 4 | `uv run --with matplotlib==3.9.2 python publications/2026-10/_build/figures.py` | `../figures/*.svg` |
| 5 | `uv run python publications/2026-10/_build/criteria_tables.py` | `../scoring-criteria.md` |
| 6 | `uv run python publications/2026-10/_build/model_pages.py` | `../models/*.md` |
| 7 | `python3 publications/2026-10/_build/index_page.py` | `../index.md` |

`rescore_logs.py` re-scored the two eval logs affected by the scorer fixes in commit
`6581141`. It moved the originals to `logs/final-superseded/`; see Methodology §7.
