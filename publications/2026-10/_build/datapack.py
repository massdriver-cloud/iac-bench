"""Consolidate the final run into runs/final/datapack/: fixtures.json (rubric
and expertise item definitions) and one <model>.json per model."""
import json, re, statistics as st, yaml
from pathlib import Path
from iacbench.report import collect_attempts, _load_prices, estimate_cost
out = Path("runs/final/datapack"); out.mkdir(parents=True, exist_ok=True)
FX = ("G001", "G002", "G003")
fixtures = {}
for fx in FX:
    r = yaml.safe_load(open(f"fixtures/generation/{fx}/rubric.yaml"))
    b = yaml.safe_load(open("fixtures/generation/baseline.yaml"))
    items = [{"id": i["id"], "weight": i.get("weight"), "posture": i.get("posture"),
              "description": " ".join((i.get("description") or "").split())} for i in r["items"] + b.get("items", [])]
    exp = [{"id": e["id"], "description": " ".join((e.get("description") or "").split())} for e in r.get("expertise", [])]
    fixtures[fx] = {"brief": open(f"fixtures/generation/{fx}/brief.md").read(), "mandatory": r.get("mandatory"),
                    "items": items, "expertise": exp, "total_weight": sum(i["weight"] or 0 for i in items)}
json.dump(fixtures, open(out / "fixtures.json", "w"), indent=1)

scores = json.load(open("runs/final/scores.json"))
judges = {fx: json.load(open(f"runs/final/judge/{fx}-opus-5-5/grades.json")) for fx in FX}
prices = _load_prices()
cost = {a.module_sha: estimate_cost(a, prices) for a in collect_attempts(Path("logs/final"))}
attempt = {a.module_sha: a for a in collect_attempts(Path("logs/final"))}
models = {}
for fx in FX:
    det = judges[fx]["detail"]
    for label, s in scores[fx].items():
        m = label.rsplit("-e", 1)[0]
        d = det[label]; a = attempt.get(s["module_sha"])
        comp = 70 * (s["mechanical"] or 0) + 0.3 * d["overall"]
        models.setdefault(m, {"model": s["model"], "fixtures": {}})["fixtures"].setdefault(fx, []).append({
            "label": label, "epoch": s["epoch"], "candidate_dir": f"runs/final/candidates/{fx}/{label}",
            "gate": s["gate"], "rubric": s["rubric"], "mechanical": s["mechanical"], "judge": d["overall"],
            "composite": comp, "mandatory_failures": s["mandatory_failures"],
            "items_lost": {k: v for k, v in s["items"].items() if float(v) < 1},
            "expertise": s["expertise"], "variables": s["variable_count"], "tf_sloc": d.get("tf_sloc"),
            "output_tokens": a.output_tokens if a else None, "seconds": round(a.duration_s) if a and a.duration_s else None,
            "cost_usd": round(cost[s["module_sha"]], 3) if cost.get(s["module_sha"]) is not None else None,
            "judge_sections": d["sections"],
            "judge_evidence": {sec: ev[:3] for sec, ev in (d.get("evidence") or {}).items()},
        })
for m, d in models.items():
    summ = {}
    for fx, samples in d["fixtures"].items():
        c = sorted(x["composite"] for x in samples)
        summ[fx] = {"composite_median": st.median(c), "composite_range": [c[0], c[-1]],
                    "rubric_median": st.median(x["rubric"] for x in samples),
                    "judge_median": st.median(x["judge"] for x in samples),
                    "gate_failures": sum(1 for x in samples if x["gate"] is False),
                    "insecure_attempts": sum(1 for x in samples if x["mandatory_failures"]),
                    "item_loss_counts": {i: sum(1 for x in samples if i in x["items_lost"]) for i in sorted({i for x in samples for i in x["items_lost"]})},
                    "expertise_rate": {e: sum(1 for x in samples if x["expertise"].get(e)) / len(samples) for e in samples[0]["expertise"]},
                    "median_variables": st.median(x["variables"] for x in samples),
                    "median_cost_usd": st.median(x["cost_usd"] for x in samples) if all(x["cost_usd"] is not None for x in samples) else None,
                    "median_output_tokens": st.median(x["output_tokens"] or 0 for x in samples),
                    "median_seconds": st.median(x["seconds"] or 0 for x in samples)}
    d["summary"] = summ
    d["overall"] = round(st.mean(summ[fx]["composite_median"] for fx in FX), 1)
    json.dump(d, open(out / f"{m}.json", "w"), indent=1)
refs = {fx: {r: {"judge": judges[fx]["detail"][r]["overall"], "sections": judges[fx]["detail"][r]["sections"]} for r in ("ref-lean", "ref-flexible")} for fx in FX}
json.dump(refs, open(out / "references.json", "w"), indent=1)
for m, d in sorted(models.items(), key=lambda kv: -kv[1]["overall"]):
    print(f"{m:24s} overall={d['overall']}", {fx: d["summary"][fx]["median_cost_usd"] for fx in FX})
