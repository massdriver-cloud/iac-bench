import json, glob, statistics as st
from pathlib import Path
PUB = Path("publications/2026-10")
S = json.load(open("runs/final/stats.json"))
M = {p.split("/")[-1][:-5]: json.load(open(p)) for p in glob.glob("runs/final/datapack/*.json") if not p.endswith(("fixtures.json", "references.json"))}
F = ("G001", "G002", "G003")
NAME = {"claude-opus-5-5": ("Claude Opus 5.5", "Anthropic", "Closed"), "claude-fable-5-1": ("Claude Fable 5.1", "Anthropic", "Closed"),
        "gpt-6-astra": ("GPT-6 Astra", "OpenAI", "Closed"), "claude-sonnet-5-5": ("Claude Sonnet 5.5", "Anthropic", "Closed"),
        "kimi-k3": ("Kimi K3", "Moonshot AI", "Open"), "gpt-6-luna": ("GPT-6 Luna", "OpenAI", "Closed"),
        "gemini-3.1-pro-preview": ("Gemini 3.1 Pro", "Google", "Closed"), "deepseek-v4-pro-0813": ("DeepSeek V4 Pro", "DeepSeek", "Open"),
        "claude-haiku-5-5": ("Claude Haiku 5.5", "Anthropic", "Closed"), "gemini-3.6-flash": ("Gemini 3.6 Flash", "Google", "Closed")}
order = S["order"]
def link(m): return f"[{NAME[m][0]}](./models/{m}.md)"
cost = {m: sum(x["cost_usd"] for f in F for x in M[m]["fixtures"][f]) for m in M}
rows = ["| Rank | Model | Developer | Weights | Overall (95% CI) | Rank interval | G001 · S3 | G002 · Cloud SQL | G003 · App Service | ✗ gate | ⚠ security | Cost, 9 attempts |",
        "|---|---|---|---|---|---|---|---|---|---|---|---|"]
for i, m in enumerate(order, 1):
    o = S["models"][m]; d = M[m]["summary"]
    g = sum(d[f]["gate_failures"] for f in F); sec = sum(d[f]["insecure_attempts"] for f in F)
    rows.append(f"| {i} | {link(m)} | {NAME[m][1]} | {NAME[m][2]} | **{o['composite']:.1f}** ({o['ci95'][0]:.1f}–{o['ci95'][1]:.1f}) | {o['rank_ci95'][0]}–{o['rank_ci95'][1]} | "
                + " | ".join(f"{d[f]['composite_median']:.1f}" for f in F) + f" | {g}/9 | {sec}/9 | ${cost[m]:.2f} |")
leader = "\n".join(rows) + "\n\nComposite = 0.70 × mechanical + 0.30 × judge. Fixture columns are medians of three attempts. ✗ = attempts whose module did not plan; ⚠ = attempts failing at least one mandatory security item. Costs are estimates at list prices on 2026-10-23 and exclude judging."
fx_rows = ["| Fixture | Field median | Best median | Most-missed rubric item (attempts that planned) | Most-missed mandatory item |", "|---|---|---|---|---|",
  f"| G001 · S3 | {st.median(s['composite'] for d in M.values() for s in d['fixtures']['G001']):.1f} | {max(M[m]['summary']['G001']['composite_median'] for m in M):.1f} (Claude Opus 5.5) | `H13` log delivery permitted: 30/30 missed | `H1` public access block: 6/30 |",
  f"| G002 · Cloud SQL | {st.median(s['composite'] for d in M.values() for s in d['fixtures']['G002']):.1f} | {max(M[m]['summary']['G002']['composite_median'] for m in M):.1f} (GPT-6 Astra) | `H11` databases dropped on removal: 24/28 | `H2` encrypted connections: 9/28 |",
  f"| G003 · App Service | {st.median(s['composite'] for d in M.values() for s in d['fixtures']['G003']):.1f} | {max(M[m]['summary']['G003']['composite_median'] for m in M):.1f} (GPT-6 Astra) | `A7` interface budget: 19/28 | `H2` basic-auth publishing: 10/28 |"]
idx = "\n".join(f"- {link(m)}: {S['models'][m]['composite']:.1f} overall" for m in order)
FILL = {
"KEY_FINDINGS": """1. **Four models form a top group:** Claude Opus 5.5 (88.9), Claude Fable 5.1, GPT-6 Astra and
   Claude Sonnet 5.5, all between 86.1 and 88.9.
   - All four have 95% rank intervals within 1–5. The models ranked below them reach fifth at
     best, except Claude Haiku 5.5, whose interval (1–9) is widened by two failed attempts.
   - Within the group, Claude Opus 5.5 is the most dependable: no failed gates, no security
     findings, and the best worst case in the field. Its weakest attempt scored 85.0. Its
     lead is not statistically decisive.
2. **Universal blind spots, regardless of vendor or rank:**
   - **S3 logging permission (G001 `H13`).** No attempt, out of 30, gave the S3 logging
     service permission to deliver access logs.
   - **Database drops (G002 `H11`).** 24 of the 28 Cloud SQL modules that planned drop a
     database's data when it is removed from the module's input.
   - **Provider version bounds (`B1`).** Constraints admitting the next major version
     appear in 19/30 AWS modules and 22/28 GCP modules. Only 2/28 Azure modules did this.
3. **Security failures come in two forms,** and different models fall into different ones.
   - 25 of 90 attempts failed a mandatory security item.
   - In 15, a security setting was exposed as a consumer input, usually with a safe default.
   - In the other 10, a setting the provider defaults insecurely was never set.
   - Four models had no security findings: Claude Opus 5.5, Claude Fable 5.1, GPT-6 Astra
     and GPT-6 Luna.
4. **The ranking does not depend on the LLM judge.** Ranked by the mechanical score alone, the
   ten models fall in exactly the same order as the composite. The judge reorders models
   only within its own component, and it catches defects the rubric cannot see (and the
   reverse).
5. **Cost buys little at the top.**
   - **Most expensive:** Claude Fable 5.1, at about $14 for nine attempts.
   - **Similar scores for less:** Claude Opus 5.5 ($3.58) and Claude Sonnet 5.5 ($1.52).
   - **Cheapest:** GPT-6 Luna scores 81.5 for five cents in total, with no security
     findings.
6. **Open weights trail the leaders but sit mid-field.**
   - Kimi K3 places fifth (82.4), ahead of GPT-6 Luna and Gemini 3.1 Pro.
   - DeepSeek V4 Pro places eighth.""",
"LEADERBOARD": leader,
"TOP_GROUP": "Claude Opus 5.5, Claude Fable 5.1, GPT-6 Astra and Claude Sonnet 5.5",
"FIXTURE_TABLE": "\n".join(fx_rows),
"BLIND_SPOTS": """These criteria were missed by most of the field.

**Access logs that cannot be delivered (G001 `H13`, 30/30 missed).**
- Nineteen S3 attempts offered no server access logging at all (`H9`).
- The rest point logging at a target bucket but never grant the S3 logging service
  permission to write to it, so S3 cannot deliver any logs.
- Every model, in every attempt, missed this.

**Databases dropped when removed from the input (G002 `H11`, 24/28 missed).**
- `google_sql_database` defaults to deleting the database, and its data, when the resource
  is removed.
- A DBA who removes a name from a module's `databases` list therefore drops that database's
  data on the next apply.
- Only GPT-6 Astra, Gemini 3.1 Pro and DeepSeek V4 Pro guarded against this, and only in
  some attempts, by setting `deletion_policy = "ABANDON"` or tying it to deletion
  protection.

**Backups that cannot be turned off (G002 `H4`/`H5`).** This one splits by rank:
- **The top models:** hardcode automated backups and point-in-time recovery to always on.
  That is safe, but it gives a DBA no way to skip backups on a disposable test instance, so
  it earns partial credit.
- **The full-credit attempts:** only Kimi K3, DeepSeek V4 Pro and the two Gemini models
  shipped backups on by default with a real opt-out.
- **Backups that outlive the instance:** no attempt kept automated backups after instance
  deletion (G002 `E1`, 0/28). By default Cloud SQL deletes them with the instance.

**Provider constraints that admit the next major version (`B1`).**

| Cloud | Attempts with such a constraint |
|---|---|
| AWS | 19/30 |
| GCP | 22/28 |
| Azure | 2/28 |

- **AWS and GCP:** the typical forms are an open-ended `>= 5.0`, or a window such as
  `>= 5.0, < 7.0` that spans two majors.
- **Azure:** modules almost always used `~> 4.0`.

The habit looks provider-specific rather than model-specific: the same models that bound
`azurerm` correctly left `aws` and `google` open.

**Expertise that only a few models showed:**
- **Cloud SQL login role** (`roles/cloudsql.instanceUser`, G002 `E6`): 13/28 granted it for
  the IAM database users they created. Without it, those users cannot log in.
- **Cloud SQL connection logging** (G002 `E8`): 12/28.
- **Key Vault references on App Service** (G003 `E5`): 6/28.""",
"SECURITY": """Each fixture has two **mandatory** items: its most severe security failures. Twenty-five of
90 attempts failed at least one.

| Pattern | Attempts | What it looks like | Models |
|---|---|---|---|
| **Secure default, open override** | 15 | The secure value is the default, but the setting is an input any consumer can change. For example, `ssl_mode` defaults to `ENCRYPTED_ONLY` while the validation also accepts `ALLOW_UNENCRYPTED_AND_ENCRYPTED`. | Gemini 3.6 Flash, Kimi K3, DeepSeek V4 Pro |
| **Insecure provider default left in place** | 10 | The module never sets the attribute, and the provider's default is insecure. On Azure, basic-auth publishing for FTP and Web Deploy is on unless disabled. | Gemini 3.1 Pro, Claude Sonnet 5.5, Claude Haiku 5.5, plus some attempts by DeepSeek V4 Pro and Gemini 3.6 Flash |

**Secure default, open override.** The doctrine treats this as a defect even when the
default is safe. A module's security posture has to hold for every consumer, and an input
that can silently weaken it will eventually be used to do so. Models in this pattern often
document the risk in the same breath: one description reads "Do not weaken this without a
security review" above a validation list that allows exactly that.

**Insecure provider default left in place.** This failure cannot be seen by reading the
source, because nothing is written down. The most-missed mandatory item in the release is
G003 `H2` (basic-auth publishing, 10/28). Several of these modules set HTTPS-only, TLS 1.2
and FTPS-off correctly in the same block, and still miss the two publishing flags the Azure
provider enables by default.

**Failed gates.** Four attempts produced modules that did not plan:
- **Two Claude Haiku 5.5 Cloud SQL attempts:** each looked up a network inside a
  placeholder project, saw `tofu plan` fail, and submitted anyway.
- **One Kimi K3 App Service attempt:** the deployment slot is missing a provider-required
  attribute.
- **One Gemini 3.6 Flash App Service attempt:** its outputs reference a resource that the
  module never declares.""",
"COMPONENTS": """**The ranking holds without the judge.** Ranked by the mechanical score alone, the ten models
fall in exactly the composite order. The judge's 30% shifts scores but never reorders the
leaderboard.

| Model | Mechanical only | Judge only | Composite rank |
|---|---|---|---|
""" + "\n".join(f"| {NAME[m][0]} | {S['models'][m]['mechanical_only']:.1f} (#{S['models'][m]['rank_mechanical_only']}) | {S['models'][m]['judge_only']:.1f} (#{S['models'][m]['rank_judge_only']}) | {i} |" for i, m in enumerate(order, 1)) + """

The two components disagree on individual modules, and the disagreements are systematic.

**What the judge misses.** It reads source, so it cannot see:
- an insecure provider default that the source never mentions. It gave the App Service
  attempts with basic-auth findings full marks on *Anti-patterns* for their hardcoded
  HTTPS and TLS settings;
- a module that does not plan. It graded the four failed-gate modules between 50 and 89.5.

**What the rubric misses.** It checks planned outcomes, so it cannot see:
- whether documentation is true;
- whether an input is ever wired to anything;
- whether a collection input breaks the plan once it is populated.

The judge scored *Documentation* 0 in 26 of 90 attempts. It found, for example, a databases
input that fails as soon as one database is declared, which the rubric credited.

**Disagreement about restraint.** The largest single gap is GPT-6 Astra on S3:
- **Rubric:** about 64. It charges for every data-hygiene item missing from a bucket that
  never expires anything.
- **Judge:** 94.7. It credits the same bucket as restrained.

A reader who rejects the rubric's view can read the judge-only column, and the reverse.

**Self-preference.** The judge is Claude Opus 5.5. Claude models take three of the top four
judge-only ranks, alongside GPT-6 Astra. But the composite order, and Claude Opus 5.5's
first place, are identical under the mechanical score alone, where no model judges any
other.""",
"COST": """Generation cost varies by a factor of about 280 across the field, and it is only loosely
related to score.

| Model | Overall | Estimated cost, 9 attempts |
|---|---|---|
""" + "\n".join(f"| {NAME[m][0]} | {S['models'][m]['composite']:.1f} | ${cost[m]:.2f} |" for m in sorted(order, key=lambda m: cost[m])) + """

The Pareto frontier, the models no other model beats on both cost and score, runs through:
- **GPT-6 Luna:** the cheapest model with no security findings.
- **Claude Sonnet 5.5:** the cheapest model in the top group.
- **Claude Opus 5.5:** the highest score.

Claude Fable 5.1 costs about four times as much as Claude Opus 5.5 for a slightly lower
score. Claude Haiku 5.5 is the second-cheapest model and would sit near the frontier, but
for its two failed Cloud SQL attempts.

Costs are estimates: token counts multiplied by list prices. They exclude judging and any
provider-specific caching discounts beyond a flat cache-read and cache-write multiplier.""",
"DOCS": """*Documentation* is the judged section most often scored 0: in 26 of 90 attempts. Nearly every
module has documentation. The zeros come from **documentation that is wrong**:
- a description that promises behavior the code does not implement;
- a stated limit that disagrees with the service;
- a comment contradicted by the line below it.

Under the doctrine, any wrong statement scores 0, however small.

| Pattern | Examples |
|---|---|
| Limits misstated | 1–35 days of WAL retention described for an edition that allows 1–7 |
| Inverted meaning | A deletion-protection input described as "whether or not to allow Terraform to destroy the instance" |
| Features that do not exist | "Least-requests load balancing" that is never configured; a staging-traffic input that feeds only an output |

**Longer documentation produces more of these errors.** The models that write long READMEs
(Claude Fable 5.1, GPT-6 Astra, Kimi K3) give the judge more claims to check:
- GPT-6 Astra had no zero.
- DeepSeek V4 Pro had six, one in every Cloud SQL and App Service attempt.
- Claude Haiku 5.5 had five.""",
"VARIANCE": """**The same model, prompt and fixture can produce very different modules.** Nine of the 30
model-fixture cells spread by more than 10 points across their three attempts. Four spread
by more than 20:

| Model · fixture | Range | Cause |
|---|---|---|
| Claude Haiku 5.5 · Cloud SQL | 25.3–91.0 | Two attempts did not plan |
| Kimi K3 · App Service | 25.3–89.4 | One attempt did not plan |
| Gemini 3.6 Flash · App Service | 15.0–62.4 | One attempt did not plan |
| DeepSeek V4 Pro · App Service | 57.8–81.8 | Basic-auth flags set in one attempt, absent in two |

Two consequences:
- **Single-sample leaderboards are fragile.** A single draw would have put Claude Haiku 5.5
  anywhere from first to ninth.
- **Consistency is itself a capability.** It separates the top group as much as peak
  quality does.

Every model in the top group has all three attempts within 11 points on every fixture.
Claude Opus 5.5's widest spread is 8.5 points.""",
"MODEL_INDEX": idx,
}
page = open(PUB / "_templates/index.md").read()
for k, v in FILL.items(): page = page.replace("{{" + k + "}}", v)
import re
assert not re.search(r"\{\{[A-Z_]+\}\}", page), re.findall(r"\{\{[A-Z_]+\}\}", page)
(PUB / "index.md").write_text(page)
print("ok", len(page.split()))
