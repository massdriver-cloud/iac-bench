import json, glob, statistics as st
import matplotlib; matplotlib.use("svg")
import matplotlib.pyplot as plt
from matplotlib.colors import LinearSegmentedColormap
S = json.load(open("runs/final/stats.json"))
M = {p.split("/")[-1][:-5]: json.load(open(p)) for p in glob.glob("runs/final/datapack/*.json") if not p.endswith(("fixtures.json", "references.json"))}
FIXN = {"G001": "G001 · S3 (AWS)", "G002": "G002 · Cloud SQL (GCP)", "G003": "G003 · App Service (Azure)"}
NAME = {"claude-opus-5-5": "Claude Opus 5.5", "claude-fable-5-1": "Claude Fable 5.1", "gpt-6-astra": "GPT-6 Astra",
        "claude-sonnet-5-5": "Claude Sonnet 5.5", "kimi-k3": "Kimi K3", "gpt-6-luna": "GPT-6 Luna",
        "gemini-3.1-pro-preview": "Gemini 3.1 Pro", "deepseek-v4-pro-0813": "DeepSeek V4 Pro",
        "claude-haiku-5-5": "Claude Haiku 5.5", "gemini-3.6-flash": "Gemini 3.6 Flash"}
SURF, INK, INK2, GRID = "#fcfcfb", "#0b0b0b", "#52514e", "#e4e3df"
S1, S2 = "#2a78d6", "#eb6834"
SEQ = LinearSegmentedColormap.from_list("blue", ["#cde2fb", "#86b6ef", "#3987e5", "#256abf", "#104281"])
plt.rcParams.update({"font.family": "DejaVu Sans", "font.size": 10, "axes.edgecolor": GRID, "axes.labelcolor": INK2,
    "xtick.color": INK2, "ytick.color": INK2, "figure.facecolor": SURF, "axes.facecolor": SURF, "svg.fonttype": "none"})
order = S["order"]; out = "publications/2026-10/figures/"
def clean(ax):
    for s in ("top", "right", "left"): ax.spines[s].set_visible(False)
    ax.tick_params(length=0); ax.grid(axis="x", color=GRID, lw=0.8); ax.set_axisbelow(True)

# 1 leaderboard with CI
fig, ax = plt.subplots(figsize=(8, 4.6)); ys = range(len(order))[::-1]
for y, m in zip(ys, order):
    o = S["models"][m]
    ax.barh(y, o["composite"], color=S1, height=0.55)
    ax.plot(o["ci95"], [y, y], color=INK, lw=1.2); ax.plot([o["ci95"][0]] * 2, [y - .12, y + .12], color=INK, lw=1.2); ax.plot([o["ci95"][1]] * 2, [y - .12, y + .12], color=INK, lw=1.2)
    ax.text(101, y, f"{o['composite']:.1f}  [{o['ci95'][0]:.0f}–{o['ci95'][1]:.0f}]  rank {o['rank_ci95'][0]}–{o['rank_ci95'][1]}", va="center", fontsize=9, color=INK2)
ax.set_yticks(list(ys)); ax.set_yticklabels([NAME[m] for m in order], color=INK); ax.set_xlim(0, 100); clean(ax)
ax.set_xlabel("Composite score (0–100): mean of per-fixture medians · whiskers: bootstrap 95% CI")
ax.set_title("Overall composite score", loc="left", color=INK, fontsize=12, fontweight="bold")
fig.tight_layout(); fig.savefig(out + "fig1-leaderboard.svg", bbox_inches="tight"); plt.close(fig)

# 2 score vs cost
fig, ax = plt.subplots(figsize=(8, 5))
pts = []
for m in order:
    cost = sum(M[m]["summary"][f]["median_cost_usd"] for f in FIXN)
    pts.append((cost, S["models"][m]["composite"], m))
for c, s, m in pts:
    ax.scatter(c, s, s=60, color=S1, edgecolor=SURF, linewidth=2, zorder=3)
    off = {"gpt-6-astra": (0, -15), "claude-fable-5-1": (0, 8), "claude-opus-5-5": (-8, 4), "kimi-k3": (6, -12)}.get(m, (6, 4))
    ax.annotate(NAME[m], (c, s), xytext=off, textcoords="offset points", fontsize=9, color=INK, ha="right" if off[0] < 0 else ("center" if off[0] == 0 else "left"))
front, best = [], -1
for c, s, m in sorted(pts):
    if s > best: front.append((c, s)); best = s
ax.plot([p[0] for p in front], [p[1] for p in front], color=INK2, lw=1, ls="--", zorder=2, label="Pareto frontier")
ax.set_xscale("log"); ax.grid(color=GRID, lw=0.8); ax.set_axisbelow(True)
from matplotlib.ticker import FuncFormatter, FixedLocator
ax.xaxis.set_major_locator(FixedLocator([0.01, 0.03, 0.1, 0.3, 1, 3]))
ax.xaxis.set_major_formatter(FuncFormatter(lambda v, _: f"${v:g}"))
for s in ("top", "right"): ax.spines[s].set_visible(False)
ax.set_xlabel("Estimated cost for one sample of each fixture (USD, log scale; list prices 2026-10-23)")
ax.set_ylabel("Overall composite"); ax.legend(frameon=False, loc="upper left")
ax.set_title("Score versus generation cost", loc="left", color=INK, fontsize=12, fontweight="bold")
fig.tight_layout(); fig.savefig(out + "fig2-cost.svg", bbox_inches="tight"); plt.close(fig)

# 3 fixture heatmap
fig, ax = plt.subplots(figsize=(7, 5))
data = [[S["models"][m]["per_fixture"][f] for f in FIXN] for m in order]
ax.imshow(data, cmap=SEQ, vmin=20, vmax=100, aspect="auto")
for i, row in enumerate(data):
    for j, v in enumerate(row):
        ax.text(j, i, f"{v:.0f}", ha="center", va="center", fontsize=10, color="#ffffff" if v > 72 else INK)
ax.set_xticks(range(3)); ax.set_xticklabels(FIXN.values(), fontsize=9); ax.set_yticks(range(len(order))); ax.set_yticklabels([NAME[m] for m in order])
ax.xaxis.tick_top(); ax.tick_params(length=0)
for s in ax.spines.values(): s.set_visible(False)
ax.set_title("Composite median by fixture", loc="left", color=INK, fontsize=12, fontweight="bold", pad=34)
fig.tight_layout(); fig.savefig(out + "fig3-fixtures.svg", bbox_inches="tight"); plt.close(fig)

# 4 mechanical vs judge
fig, ax = plt.subplots(figsize=(8, 4.8)); ys = list(range(len(order)))[::-1]
for y, m in zip(ys, order):
    o = S["models"][m]
    ax.plot([o["mechanical_only"], o["judge_only"]], [y, y], color=GRID, lw=2, zorder=1)
    ax.scatter(o["mechanical_only"], y, s=60, color=S1, edgecolor=SURF, linewidth=2, zorder=3, label="Mechanical only (×100)" if y == ys[0] else None)
    ax.scatter(o["judge_only"], y, s=60, color=S2, marker="D", edgecolor=SURF, linewidth=2, zorder=3, label="Judge only" if y == ys[0] else None)
ax.set_yticks(ys); ax.set_yticklabels([NAME[m] for m in order], color=INK); ax.set_xlim(40, 100); clean(ax)
ax.legend(frameon=False, loc="lower left", bbox_to_anchor=(0, 1.0), ncol=2); ax.set_xlabel("Score (0–100), mean of per-fixture medians")
ax.set_title("The two scoring components, separately", loc="left", color=INK, fontsize=12, fontweight="bold", pad=28)
fig.tight_layout(); fig.savefig(out + "fig4-components.svg", bbox_inches="tight"); plt.close(fig)

# 5 rubric item heatmap: items failed by >= 6 of 30 samples
fx = json.load(open("runs/final/datapack/fixtures.json"))
cols = []
for f in FIXN:
    for it in fx[f]["items"]:
        lost = sum(1 for m in M for s in M[m]["fixtures"][f] if s["gate"] is not False and it["id"] in s["items_lost"])
        if lost >= 6: cols.append((f, it["id"]))
grid = [[sum(1 for s in M[m]["fixtures"][f] if s["gate"] is not False and i not in s["items_lost"]) / max(1, sum(1 for s in M[m]["fixtures"][f] if s["gate"] is not False)) for f, i in cols] for m in order]
fig, ax = plt.subplots(figsize=(11, 5))
ax.imshow(grid, cmap=SEQ, vmin=0, vmax=1, aspect="auto")
for r, row in enumerate(grid):
    for c, v in enumerate(row):
        ax.text(c, r, f"{v*100:.0f}", ha="center", va="center", fontsize=8, color="#ffffff" if v > 0.6 else INK)
ax.set_xticks(range(len(cols))); ax.set_xticklabels([f"{f}\n{i.replace('_provider_constraints','')}" for f, i in cols], fontsize=8)
ax.set_yticks(range(len(order))); ax.set_yticklabels([NAME[m] for m in order]); ax.xaxis.tick_top(); ax.tick_params(length=0)
for s in ax.spines.values(): s.set_visible(False)
ax.set_title("Full-credit rate on the most-missed rubric items (% of samples that planned)", loc="left", color=INK, fontsize=12, fontweight="bold", pad=40)
fig.tight_layout(); fig.savefig(out + "fig5-items.svg", bbox_inches="tight"); plt.close(fig)

# 6 findings
fig, ax = plt.subplots(figsize=(8, 4.6)); ys = list(range(len(order)))[::-1]
for y, m in zip(ys, order):
    ins = sum(M[m]["summary"][f]["insecure_attempts"] for f in FIXN); gate = sum(M[m]["summary"][f]["gate_failures"] for f in FIXN)
    ax.barh(y + 0.18, ins, height=0.34, color=S1, label="Attempts with a security finding" if y == ys[0] else None)
    ax.barh(y - 0.18, gate, height=0.34, color=S2, label="Attempts that failed the gate" if y == ys[0] else None)
    ax.text(ins + 0.1, y + 0.18, str(ins), va="center", fontsize=8, color=INK2); ax.text(gate + 0.1, y - 0.18, str(gate), va="center", fontsize=8, color=INK2)
ax.set_yticks(ys); ax.set_yticklabels([NAME[m] for m in order], color=INK); ax.set_xlim(0, 9); clean(ax)
ax.set_xlabel("Attempts out of 9 (3 fixtures × 3 samples)"); ax.legend(frameon=False, loc="upper right")
ax.set_title("Security findings and failed gates", loc="left", color=INK, fontsize=12, fontweight="bold")
fig.tight_layout(); fig.savefig(out + "fig6-findings.svg", bbox_inches="tight"); plt.close(fig)
print("cols:", cols)
