"""Bootstrap CIs, pairwise win probabilities and sensitivity rankings -> runs/final/stats.json"""
import json, glob, random, statistics as st
random.seed(20261023)
M = {p.split("/")[-1][:-5]: json.load(open(p)) for p in glob.glob("runs/final/datapack/*.json")
     if not p.endswith(("fixtures.json", "references.json"))}
FX = ("G001", "G002", "G003"); B = 10000
def overall(d, key, pick=None):
    return st.mean(st.median((pick or (lambda s: s))([s[key] for s in d["fixtures"][f]]) if False else [s[key] for s in d["fixtures"][f]]) for f in FX)
def boot(d, key):
    vals = []
    for _ in range(B):
        vals.append(st.mean(st.median(random.choices([s[key] for s in d["fixtures"][f]], k=3)) for f in FX))
    return vals
out = {"bootstrap_resamples": B, "method": "resample each model's 3 samples per fixture with replacement; statistic = mean over fixtures of the per-fixture median", "models": {}}
draws = {}
for m, d in M.items():
    for s in [s for f in FX for s in d["fixtures"][f]]:
        s["mech100"] = 100 * (s["mechanical"] or 0)
    bc = boot(d, "composite"); draws[m] = bc
    bc_sorted = sorted(bc)
    out["models"][m] = {
        "composite": overall(d, "composite"), "ci95": [bc_sorted[int(0.025 * B)], bc_sorted[int(0.975 * B)]],
        "mechanical_only": overall(d, "mech100"), "judge_only": overall(d, "judge"),
        "per_fixture": {f: st.median(s["composite"] for s in d["fixtures"][f]) for f in FX},
    }
names = sorted(out["models"], key=lambda m: -out["models"][m]["composite"])
out["order"] = names
out["win_probability"] = {a: {b: sum(1 for x, y in zip(draws[a], draws[b]) if x > y) / B for b in names if b != a} for a in names}
for k in ("composite", "mechanical_only", "judge_only"):
    rank = sorted(names, key=lambda m: -out["models"][m][k])
    for i, m in enumerate(rank, 1): out["models"][m][f"rank_{k}"] = i
# rank intervals (LMArena-style): each model's rank in every joint bootstrap draw
ranks = {m: [] for m in names}
for i in range(B):
    order = sorted(names, key=lambda m: -draws[m][i])
    for r, m in enumerate(order, 1): ranks[m].append(r)
for m in names:
    rs = sorted(ranks[m]); out["models"][m]["rank_ci95"] = [rs[int(0.025 * B)], rs[int(0.975 * B) - 1]]
json.dump(out, open("runs/final/stats.json", "w"), indent=1)
for m in names:
    o = out["models"][m]
    print(f"{m:24s} {o['composite']:5.1f} [{o['ci95'][0]:5.1f},{o['ci95'][1]:5.1f}]  mech={o['mechanical_only']:5.1f}(#{o['rank_mechanical_only']}) judge={o['judge_only']:5.1f}(#{o['rank_judge_only']})")
print({m:out["models"][m]["rank_ci95"] for m in names})
print("P(opus>fable)=%.2f P(opus>astra)=%.2f P(opus>sonnet)=%.2f P(fable>sonnet)=%.2f P(sonnet>kimi)=%.2f P(kimi>luna)=%.2f" % tuple(out["win_probability"][a][b] for a,b in [("claude-opus-5-5","claude-fable-5-1"),("claude-opus-5-5","gpt-6-astra"),("claude-opus-5-5","claude-sonnet-5-5"),("claude-fable-5-1","claude-sonnet-5-5"),("claude-sonnet-5-5","kimi-k3"),("kimi-k3","gpt-6-luna")]))
