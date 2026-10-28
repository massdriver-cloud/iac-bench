import json, glob
fx = json.load(open("runs/final/datapack/fixtures.json"))
M = {p.split("/")[-1][:-5]: json.load(open(p)) for p in glob.glob("runs/final/datapack/*.json")
     if not p.endswith(("fixtures.json", "references.json"))}
NAMES = {"G001": "S3 bucket (AWS)", "G002": "Cloud SQL for PostgreSQL (GCP)", "G003": "App Service (Azure)"}
POST = {"hardcoded": "hardcoded", "default_on": "on by default", "reachable": "offered", "ladder": "graded", "budget": "budget", None: "Direct"}
out = []
for f in ("G001", "G002", "G003"):
    samples = [s for d in M.values() for s in d["fixtures"][f]]
    gated = [s for s in samples if s["gate"] is not False]
    out.append(f"#### {f}: {NAMES[f]}\n")
    out.append(f"Mandatory (security findings): {', '.join(fx[f]['mandatory'])}. Total rubric weight: {fx[f]['total_weight']}.\n")
    out.append("| ID | Weight | Kind | What passes | Full credit (attempts that planned) |")
    out.append("|---|---|---|---|---|")
    for it in fx[f]["items"]:
        full = sum(1 for s in gated if it["id"] not in s["items_lost"])
        desc = it["description"].replace("|", "\\|")
        desc = desc.replace(" — ", ": ", 1).replace(" — ", "; ").replace("—", ", ")
        if len(desc) > 260: desc = desc[:257].rsplit(" ", 1)[0] + "…"
        mand = " **(mandatory)**" if it["id"] in fx[f]["mandatory"] else ""
        out.append(f"| `{it['id']}`{mand} | {it['weight']} | {POST.get(it.get('posture'), it.get('posture'))} | {desc} | {full}/{len(gated)} |")
    out.append("")
    out.append("| Expertise item | What it detects | Present |")
    out.append("|---|---|---|")
    for e in fx[f]["expertise"]:
        n = sum(1 for s in gated if s["expertise"].get(e["id"]))
        edesc = e['description'].replace('|', '/').replace(" — ", ": ", 1).replace(" — ", "; ").replace("—", ", ")
        out.append(f"| `{e['id'].split('_')[0]}` {e['id'].split('_',1)[1].replace('_',' ')} | {edesc} | {n}/{len(gated)} |")
    out.append("")
tables = "\n".join(out)
tmpl = open("publications/2026-10/_templates/scoring-criteria.md").read()
open("publications/2026-10/scoring-criteria.md", "w").write(tmpl.replace("{{CRITERIA_TABLES}}", tables))
print("\n".join(out)[:3000])
