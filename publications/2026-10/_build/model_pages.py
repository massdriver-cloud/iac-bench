import json, glob, statistics as st, yaml
from pathlib import Path
PUB = Path("publications/2026-10"); TPL = PUB / "_templates/models"
S = json.load(open("runs/final/stats.json")); prices = yaml.safe_load(open("prices.yaml"))
M = {p.split("/")[-1][:-5]: json.load(open(p)) for p in glob.glob("runs/final/datapack/*.json") if not p.endswith(("fixtures.json", "references.json"))}
META = {
 "claude-opus-5-5": ("Claude Opus 5.5", "Anthropic", "Anthropic API", "Closed"),
 "claude-fable-5-1": ("Claude Fable 5.1", "Anthropic", "Anthropic API", "Closed"),
 "claude-sonnet-5-5": ("Claude Sonnet 5.5", "Anthropic", "Anthropic API", "Closed"),
 "claude-haiku-5-5": ("Claude Haiku 5.5", "Anthropic", "Anthropic API", "Closed"),
 "gpt-6-astra": ("GPT-6 Astra", "OpenAI", "OpenAI API (Responses)", "Closed"),
 "gpt-6-luna": ("GPT-6 Luna", "OpenAI", "OpenAI API (Responses)", "Closed"),
 "gemini-3.1-pro-preview": ("Gemini 3.1 Pro", "Google", "Gemini API", "Closed"),
 "gemini-3.6-flash": ("Gemini 3.6 Flash", "Google", "Gemini API", "Closed"),
 "kimi-k3": ("Kimi K3", "Moonshot AI", "OpenRouter", "Open"),
 "deepseek-v4-pro-0813": ("DeepSeek V4 Pro", "DeepSeek", "OpenRouter", "Open"),
}
EXCERPTS = {
 "claude-opus-5-5": [("G002/claude-opus-5-5-e3/main.tf", 7, 17)],
 "claude-fable-5-1": [("G002/claude-fable-5-1-e1/main.tf", 11, 21)],
 "gpt-6-astra": [("G002/gpt-6-astra-e3/main.tf", 102, 116)],
 "claude-sonnet-5-5": [("G003/claude-sonnet-5-5-e1/main.tf", 119, 133)],
 "kimi-k3": [("G002/kimi-k3-e1/variables.tf", 200, 209)],
 "gpt-6-luna": [("G003/gpt-6-luna-e1/main.tf", 58, 63)],
 "gemini-3.1-pro-preview": [("G003/gemini-3.1-pro-preview-e1/main.tf", 45, 58)],
 "deepseek-v4-pro-0813": [("G002/deepseek-v4-pro-0813-e3/main.tf", 30, 38)],
 "claude-haiku-5-5": [("G002/claude-haiku-5-5-e1/main.tf", 4, 7), ("G002/claude-haiku-5-5-e1/minimal.tfvars", 1, 4)],
 "gemini-3.6-flash": [("G002/gemini-3.6-flash-e1/variables.tf", 65, 75)],
}
CAPTION = {
 "claude-opus-5-5": "The DBA team keeps an open-ended flags input, but the module's own flags are merged last, so no input can switch off IAM authentication or connection auditing.",
 "claude-fable-5-1": "The same pattern as the leader, with a broader enforced audit set: connections, disconnections, checkpoints, lock waits and temporary files are always logged.",
 "gpt-6-astra": "Project-level Cloud SQL roles granted with an IAM condition on this one instance. Without the condition, the same grant would allow login to every instance in the project.",
 "claude-sonnet-5-5": "HTTPS, FTPS-off and TLS 1.2 are hardcoded, but neither basic-auth publishing flag is set. Both stay at the provider default (on). This is the cause of the `H2` finding.",
 "kimi-k3": "The description states the standard and warns against weakening it, yet the validation accepts the unencrypted mode. That one list entry cost `H2` in all three Cloud SQL attempts.",
 "gpt-6-luna": "Registry credentials are routed through app settings, although the same module creates a system-assigned managed identity that could pull images instead.",
 "gemini-3.1-pro-preview": "An otherwise complete resource that never sets `https_only` or the basic-auth publishing flags. The same omission appears on all six App Service web apps and slots this model wrote.",
 "deepseek-v4-pro-0813": "The comment says SSL is enforced end to end, and the next line lets a caller turn it off. Public IP is also an input.",
 "claude-haiku-5-5": "A reasonable network lookup, which the reference module also uses, made unplannable by a required `project_id` that the model filled with a placeholder.",
 "gemini-3.6-flash": "Both defaults are secure, but each control is an unvalidated consumer input, and the description advertises the unencrypted mode. This fails both mandatory Cloud SQL items.",
}
FXN = {"G001": "G001 · S3", "G002": "G002 · Cloud SQL", "G003": "G003 · App Service"}
def price_for(m):
    for k, p in prices["models"].items():
        if k in m: return p
for m, d in M.items():
    name, vendor, access, weights = META[m]; o = S["models"][m]; p = price_for(m)
    total = sum(x["cost_usd"] or 0 for f in FXN for x in d["fixtures"][f])
    facts = "\n".join([
        "| | |", "|---|---|",
        f"| Developer | {vendor} |", f"| API identifier | `{d['model'].split('/',1)[1]}` |", f"| Access | {access} |", f"| Weights | {weights} |",
        f"| List price (USD / M tokens, in / out) | {p['input']:.2f} / {p['output']:.2f} (OpenRouter, 2026-10-23) |",
        f"| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |",
        f"| Attempts | 9 (3 fixtures × 3 samples) |",
        f"| **Overall composite** | **{o['composite']:.1f}** (95% CI {o['ci95'][0]:.1f}–{o['ci95'][1]:.1f}) |",
        f"| Rank | {o['rank_composite']} of 10 (95% rank interval {o['rank_ci95'][0]}–{o['rank_ci95'][1]}) |",
        f"| Mechanical only / judge only | {o['mechanical_only']:.1f} (rank {o['rank_mechanical_only']}) / {o['judge_only']:.1f} (rank {o['rank_judge_only']}) |",
        f"| Failed gates · insecure attempts | {sum(d['summary'][f]['gate_failures'] for f in FXN)}/9 · {sum(d['summary'][f]['insecure_attempts'] for f in FXN)}/9 |",
        f"| Estimated cost, all 9 attempts | ${total:.2f} |",
    ])
    rows = ["| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |",
            "|---|---|---|---|---|---|---|---|---|---|---|"]
    for f, label in FXN.items():
        s = d["summary"][f]; xs = d["fixtures"][f]
        fxdef = json.load(open("runs/final/datapack/fixtures.json"))[f]; nexp = len(fxdef["expertise"])
        planned = [x for x in xs if x["gate"] is not False]
        exp = st.median(sum(1 for v in x["expertise"].values() if v) for x in planned) if planned else 0
        finds = sorted({i for x in xs for i in x["mandatory_failures"] or []})
        rows.append(f"| {label} | {s['composite_median']:.1f} ({s['composite_range'][0]:.1f}–{s['composite_range'][1]:.1f}) | {s['rubric_median']:.3f} | {exp:g}/{nexp} | {s['judge_median']:.1f} | {s['gate_failures']}/3 | {s['insecure_attempts']}/3{(' (' + ', '.join('`'+i+'`' for i in finds) + ')') if finds else ''} | {s['median_variables']:g} | {s['median_output_tokens']:,.0f} | {s['median_seconds']:.0f} s | ${s['median_cost_usd']:.3f} |")
    lost = {}
    for f in FXN:
        planned = [x for x in d["fixtures"][f] if x["gate"] is not False]
        counts = {}
        for x in planned:
            for i in x["items_lost"]: counts[i] = counts.get(i, 0) + 1
        short = lambda i: i.replace('_provider_constraints', '').replace('_descriptions', '')
        key = lambda i: (i[0], int(''.join(ch for ch in i[1:].split('_')[0] if ch.isdigit()) or 0))
        parts = [f"`{short(i)}` {c}/{len(planned)}" for i, c in sorted(counts.items(), key=lambda kv: key(kv[0]))]
        gated = len(d["fixtures"][f]) - len(planned)
        if gated: parts.append(f"{gated} attempt{'s' if gated > 1 else ''} failed the gate")
        if parts: lost[f] = parts
    scores = ("## Scores\n\n" + "\n".join(rows) + "\n\nRubric items not at full credit, counted over attempts that planned: "
              + "; ".join(f"{f}: " + ", ".join(v) for f, v in lost.items()) + ". Definitions are in [Scoring criteria](../scoring-criteria.md).")
    ex = ["## Representative excerpt", ""]
    for path, a, b in EXCERPTS[m]:
        lines = open(f"runs/final/candidates/{path}").read().splitlines()[a-1:b]
        lang = "hcl"
        ex += [f"`{path}` lines {a}–{b}", "", f"```{lang}", *lines, "```", ""]
    ex.append(CAPTION[m])
    page = open(TPL / f"{m}.md").read().replace("{{FACTS}}", facts).replace("{{SCORES}}", scores).replace("{{EXCERPT}}", "\n".join(ex))
    page = "---\ntitle: \"" + name + " — iac-bench 2026-10\"\nrelease: \"2026-10\"\n---\n\n" + page + "\n\n---\n\n[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)\n"
    (PUB / "models" / f"{m}.md").write_text(page)
print("ok")
