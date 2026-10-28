"""Export the 2026-10 publication as marketing-site blog posts.
Usage: python3 publications/2026-10/_build/to_blog.py ../marketing-site"""
import json, re, shutil, sys
from pathlib import Path
PUB = Path("publications/2026-10"); SITE = Path(sys.argv[1])
BLOGS = SITE / "content/blogs"; ASSETS = SITE / "public/assets/iac-bench-2026-10"
DATE, AUTHOR = "2026-10-28", "Chris Hill"
TAGS = ["AI", "OpenTofu", "iac", "benchmarks"]
S = json.load(open("runs/final/stats.json"))
NAME = {"claude-opus-5-5": "Claude Opus 5.5", "claude-fable-5-1": "Claude Fable 5.1", "gpt-6-astra": "GPT-6 Astra",
        "claude-sonnet-5-5": "Claude Sonnet 5.5", "kimi-k3": "Kimi K3", "gpt-6-luna": "GPT-6 Luna",
        "gemini-3.1-pro-preview": "Gemini 3.1 Pro", "deepseek-v4-pro-0813": "DeepSeek V4 Pro",
        "claude-haiku-5-5": "Claude Haiku 5.5", "gemini-3.6-flash": "Gemini 3.6 Flash"}
SLUG = {"index": "iac-bench-2026-10-results", "methodology": "iac-bench-2026-10-methodology",
        "scoring-criteria": "iac-bench-2026-10-scoring-criteria", **{m: f"iac-bench-2026-10-{m.replace('.', '-')}" for m in NAME}}
POSTS = [
    ("index", PUB / "index.md", "How Well Do LLMs Write Infrastructure Modules? iac-bench 2026-10 Results",
     "We asked ten language models to write reusable OpenTofu modules for AWS, GCP and Azure, then scored 90 modules against real plans and a calibrated judge. Here is how they did and the patterns behind the scores.", "cover-results.png"),
    ("methodology", PUB / "methodology.md", "iac-bench 2026-10 Methodology",
     "How the iac-bench 2026-10 results were produced: the briefs, the evaluation setup, mechanical scoring against real tofu plans, the calibrated LLM judge, statistics and limitations.", "cover-methodology.png"),
    ("scoring-criteria", PUB / "scoring-criteria.md", "iac-bench 2026-10 Scoring Criteria",
     "Reference for every criterion behind an iac-bench score: each rubric item, expertise item and judged doctrine section, with weights and how many attempts passed.", "cover-scoring-criteria.png"),
] + [(m, PUB / "models" / f"{m}.md", f"{NAME[m]} on iac-bench 2026-10",
      f"How {NAME[m]} did on iac-bench 2026-10: an overall composite of {S['models'][m]['composite']:.1f}, scores per fixture, strengths, weaknesses and the patterns in its OpenTofu modules.",
      f"cover-{m}.png") for m in S["order"]]

def link(target):
    path, _, anchor = target.partition("#")
    name = Path(path).stem
    if path.startswith(("./figures/", "../figures/", "figures/")):
        return f"/assets/iac-bench-2026-10/{Path(path).name}"
    if name in SLUG and path.endswith(".md"):
        return f"/blogs/{SLUG[name]}" + (f"#{anchor}" if anchor else "")
    if not path and anchor:
        return f"#{anchor}"
    return None

def convert(text):
    text = re.sub(r"\A---\n.*?\n---\n", "", text, flags=re.S).lstrip()
    text = re.sub(r"\A# .*\n", "", text).lstrip()
    def fix(mm):
        new = link(mm.group(2))
        if new is None and not mm.group(2).startswith("http"):
            raise SystemExit(f"unresolved link: {mm.group(2)}")
        return f"{mm.group(1)}({new or mm.group(2)})"
    return re.sub(r"(!?\[[^\]]*\])\(([^)\s]+)\)", fix, text)

ASSETS.mkdir(parents=True, exist_ok=True)
for f in (PUB / "figures").glob("*.svg"): shutil.copy(f, ASSETS / f.name)
for f in Path("runs/scratch/covers").glob("cover-*.png"): shutil.copy(f, ASSETS / f.name)
for key, src, title, desc, cover in POSTS:
    body = convert(src.read_text())
    words = len(re.sub(r"```.*?```", "", body, flags=re.S).split())
    fm = "\n".join(["---", f"title: {json.dumps(title)}", f"description: {json.dumps(desc)}", f"date: '{DATE}'",
                    f"author: {AUTHOR}", "category: Engineering", f"coverImage: /assets/iac-bench-2026-10/{cover}",
                    "tags:", *[f"  - {t}" for t in TAGS], f"readTime: '{max(1, round(words / 230))} min'", "---"])
    post = f"{fm}\n\n# {title}\n\n<PostBylineShare />\n\n<PostTags />\n\n{body}"
    assert "—" not in post, f"em dash in {key}"
    (BLOGS / f"{SLUG[key]}.md").write_text(post)
    print(f"{SLUG[key]}.md  {words} words")
