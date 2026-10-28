"""Blog cover images (1600x840) for the marketing-site export."""
import json, sys
from pathlib import Path
import matplotlib; matplotlib.use("agg")
import matplotlib.pyplot as plt
OUT = Path(sys.argv[1]); OUT.mkdir(parents=True, exist_ok=True)
BG, INK, MUTED, TEAL, SLATE = "#0A0A0B", "#FAFAFA", "#A1A1AA", "#2DD4BF", "#27272A"
S = json.load(open("runs/final/stats.json"))
NAME = {"claude-opus-5-5": "Claude Opus 5.5", "claude-fable-5-1": "Claude Fable 5.1", "gpt-6-astra": "GPT-6 Astra",
        "claude-sonnet-5-5": "Claude Sonnet 5.5", "kimi-k3": "Kimi K3", "gpt-6-luna": "GPT-6 Luna",
        "gemini-3.1-pro-preview": "Gemini 3.1 Pro", "deepseek-v4-pro-0813": "DeepSeek V4 Pro",
        "claude-haiku-5-5": "Claude Haiku 5.5", "gemini-3.6-flash": "Gemini 3.6 Flash"}
def canvas():
    fig = plt.figure(figsize=(16, 8.4), dpi=100); fig.patch.set_facecolor(BG)
    return fig
def save(fig, name): fig.savefig(OUT / name, facecolor=BG); plt.close(fig)

fig = canvas()
fig.text(0.06, 0.60, "How well do language models\nwrite infrastructure modules?", color=INK, fontsize=50, weight="bold", va="center", linespacing=1.15)
fig.text(0.06, 0.40, "iac-bench 2026-10  ·  10 models  ·  3 clouds  ·  90 OpenTofu modules", color=MUTED, fontsize=26)
ax = fig.add_axes([0.06, 0.07, 0.88, 0.24]); ax.set_facecolor(BG)
order = S["order"]; vals = [S["models"][m]["composite"] for m in order]
ax.bar(range(len(order)), vals, color=[TEAL if i < 4 else SLATE for i in range(len(order))], width=0.7)
ax.set_ylim(0, 100); ax.axis("off")
for i, (m, v) in enumerate(zip(order, vals)):
    ax.text(i, v + 3, f"{v:.0f}", ha="center", color=INK if i < 4 else MUTED, fontsize=16)
save(fig, "cover-results.png")

for name, title, sub in [("cover-methodology.png", "Methodology", "iac-bench 2026-10  ·  briefs, scoring, judge calibration, statistics"),
                         ("cover-scoring-criteria.png", "Scoring criteria", "iac-bench 2026-10  ·  every rubric item, expertise item and judged section")]:
    fig = canvas()
    fig.text(0.06, 0.55, title, color=INK, fontsize=72, weight="bold", va="center")
    fig.text(0.06, 0.38, sub, color=MUTED, fontsize=28)
    save(fig, name)

for m in order:
    o = S["models"][m]
    fig = canvas()
    fig.text(0.06, 0.58, NAME[m], color=INK, fontsize=72, weight="bold", va="center")
    fig.text(0.06, 0.40, "iac-bench 2026-10 model report", color=MUTED, fontsize=30)
    fig.text(0.06, 0.16, f"{o['composite']:.1f}", color=TEAL, fontsize=96, weight="bold", va="center")
    fig.text(0.30, 0.19, "overall composite", color=MUTED, fontsize=24, va="center")
    fig.text(0.30, 0.12, f"rank {o['rank_composite']} of 10  ·  95% rank interval {o['rank_ci95'][0]}–{o['rank_ci95'][1]}", color=MUTED, fontsize=24, va="center")
    save(fig, f"cover-{m}.png")
print("covers:", len(list(OUT.glob("cover-*.png"))))
