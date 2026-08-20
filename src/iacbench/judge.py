"""Layer 3: pairwise LLM judge for generation fixtures.

UNTRUSTED BY DEFAULT. Judge output is experimental until it demonstrates
agreement with a human-ranked calibration set (`--human`). Judged scores are
reported in their own column and never merged into mechanical scores.

Design:
- blind: candidates are presented as "Module 1"/"Module 2" with no authorship
- order-debiased: every pair is judged in both presentation orders
- aggregated with Bradley-Terry, so scores come from comparisons, not absolute
  rubric grades (which LLM judges are bad at)

Every judgment is appended to judgments.jsonl with the judge model, prompt
hash, presentation order, and raw rationale — re-aggregation is free.
"""

from __future__ import annotations

import asyncio
import hashlib
import itertools
import json
import re
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import yaml

from .paths import PROMPTS_DIR, REPO_ROOT

DEFAULT_PRINCIPLES = REPO_ROOT / "docs" / "good-opentofu.md"
MAX_MODULE_CHARS = 30_000
_WINNER_RE = re.compile(r"WINNER:\s*(?:MODULE\s*)?([12])", re.IGNORECASE)


def render_module(module_dir: Path) -> str:
    parts = []
    for tf in sorted(Path(module_dir).rglob("*.tf")):
        if ".terraform" in tf.parts:
            continue
        rel = tf.relative_to(module_dir)
        parts.append(f"### {rel}\n```hcl\n{tf.read_text(errors='replace')}\n```")
    text = "\n\n".join(parts)
    if len(text) > MAX_MODULE_CHARS:
        text = text[:MAX_MODULE_CHARS] + f"\n[truncated {len(text) - MAX_MODULE_CHARS} chars]"
    return text


@dataclass
class Judgment:
    fixture: str
    judge_model: str
    prompt_sha256: str
    principles_sha256: str | None   # edition of docs/good-opentofu.md in force
    a: str                # candidate label presented in slot 1
    b: str                # candidate label presented in slot 2
    winner: str | None    # candidate label, None if unparseable
    rationale: str
    judged_at: str


async def _judge_once(model, system_prompt: str, brief: str, m1: str, m2: str) -> tuple:
    from inspect_ai.model import ChatMessageSystem, ChatMessageUser

    user = (
        f"# The brief both modules were built against\n\n{brief}\n\n"
        f"# Module 1\n\n{m1}\n\n# Module 2\n\n{m2}"
    )
    output = await model.generate(
        [ChatMessageSystem(content=system_prompt), ChatMessageUser(content=user)]
    )
    text = output.completion or ""
    match = _WINNER_RE.search(text)
    slot = int(match.group(1)) if match else None
    return slot, text.strip()


async def run_judge(
    fixture_id: str,
    brief: str,
    candidates: dict,          # label -> module dir
    judge_model: str,
    out_dir: Path,
    rounds: int = 1,
) -> dict:
    from inspect_ai.model import get_model

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    system_prompt = (PROMPTS_DIR / "judge-pairwise.md").read_text()
    prompt_sha = hashlib.sha256(system_prompt.encode()).hexdigest()[:16]

    # The org's living definition of quality anchors the judge; hash the
    # edition into every judgment. Never shown to candidate models.
    principles_sha = None
    if DEFAULT_PRINCIPLES.is_file():
        principles = DEFAULT_PRINCIPLES.read_text()
        principles_sha = hashlib.sha256(principles.encode()).hexdigest()[:16]
        system_prompt += (
            "\n\n# The organization's definition of good OpenTofu"
            " (authoritative for this review)\n\n" + principles
        )
    rendered = {label: render_module(d) for label, d in candidates.items()}
    model = get_model(judge_model)

    labels = sorted(candidates)
    tasks = []
    order: list = []
    for a, b in itertools.combinations(labels, 2):
        for _ in range(rounds):
            for first, second in ((a, b), (b, a)):
                order.append((first, second))
                tasks.append(_judge_once(model, system_prompt, brief, rendered[first], rendered[second]))
    results = await asyncio.gather(*tasks, return_exceptions=True)

    # BT aggregates over ALL accumulated judgments for this out_dir (same
    # candidates/config appended across runs), not just this run's batch
    judgments: list = []
    jsonl_path = out_dir / "judgments.jsonl"
    if jsonl_path.is_file():
        for line in jsonl_path.read_text().splitlines():
            if line.strip():
                prior = json.loads(line)
                judgments.append(Judgment(**prior))
    with open(jsonl_path, "a") as f:
        for (first, second), result in zip(order, results, strict=True):
            if isinstance(result, Exception):
                slot, text = None, f"[error: {result}]"
            else:
                slot, text = result
            winner = {1: first, 2: second}.get(slot)
            j = Judgment(
                fixture=fixture_id,
                judge_model=judge_model,
                prompt_sha256=prompt_sha,
                principles_sha256=principles_sha,
                a=first,
                b=second,
                winner=winner,
                rationale=text[:2000],
                judged_at=datetime.now(timezone.utc).isoformat(),
            )
            judgments.append(j)
            f.write(json.dumps(asdict(j)) + "\n")

    scores = bradley_terry(labels, judgments)
    summary = {
        "fixture": fixture_id,
        "judge_model": judge_model,
        "prompt_sha256": prompt_sha,
        "principles_sha256": principles_sha,
        "status": "experimental (not calibrated against human ranking)",
        "candidates": labels,
        "judgments": len(judgments),
        "unparseable": sum(1 for j in judgments if j.winner is None),
        "bt_scores": scores,
        "pair_wins": _pair_table(labels, judgments),
    }
    (out_dir / "scores.json").write_text(json.dumps(summary, indent=2))
    return summary


def _pair_table(labels: list, judgments: list) -> dict:
    table: dict = {}
    for a, b in itertools.combinations(labels, 2):
        wins_a = sum(1 for j in judgments if {j.a, j.b} == {a, b} and j.winner == a)
        wins_b = sum(1 for j in judgments if {j.a, j.b} == {a, b} and j.winner == b)
        table[f"{a} vs {b}"] = f"{wins_a}-{wins_b}"
    return table


def bradley_terry(labels: list, judgments: list, iterations: int = 500) -> dict:
    """MM-algorithm Bradley-Terry strengths, normalized to sum 1."""
    wins = {label: 0 for label in labels}
    games: dict = {}
    for j in judgments:
        if j.winner is None:
            continue
        wins[j.winner] = wins.get(j.winner, 0) + 1
        key = frozenset((j.a, j.b))
        games[key] = games.get(key, 0) + 1

    pi = {label: 1.0 for label in labels}
    for _ in range(iterations):
        new = {}
        for i in labels:
            denom = sum(
                games.get(frozenset((i, k)), 0) / (pi[i] + pi[k])
                for k in labels
                if k != i
            )
            new[i] = (wins[i] / denom) if denom > 0 else pi[i]
        total = sum(new.values()) or 1.0
        pi = {label: v / total for label, v in new.items()}
    return {label: round(v, 4) for label, v in sorted(pi.items(), key=lambda kv: -kv[1])}


_SECTION_RE = re.compile(r"^## (.+)$", re.MULTILINE)
_GRADE_LINE_RE = re.compile(
    r"SECTION:\s*(.+?)\s*\|\s*SCORE:\s*(NA|[0-4])", re.IGNORECASE
)


def _median(values: list) -> float:
    values = sorted(values)
    n = len(values)
    mid = n // 2
    return values[mid] if n % 2 else (values[mid - 1] + values[mid]) / 2


async def _grade_once(model, system_prompt: str, doc: str, brief: str, module_text: str) -> dict:
    from inspect_ai.model import ChatMessageSystem, ChatMessageUser

    user = (
        f"# The organization's standards document\n\n{doc}\n\n"
        f"# The brief this module was built against\n\n{brief}\n\n"
        f"# The module to grade\n\n{module_text}"
    )
    output = await model.generate(
        [ChatMessageSystem(content=system_prompt), ChatMessageUser(content=user)]
    )
    scores: dict = {}
    for match in _GRADE_LINE_RE.finditer(output.completion or ""):
        section, raw = match.group(1).strip(), match.group(2).upper()
        scores[section] = None if raw == "NA" else int(raw)
    return scores


async def run_grade(
    fixture_id: str,
    brief: str,
    candidates: dict,
    judge_model: str,
    out_dir: Path,
    samples: int = 3,
) -> dict:
    """Absolute grading: each candidate scored 0-4 per standards-doc section,
    independently of every other candidate. Medians across samples; overall
    grade = mean of applicable section medians, scaled to 0-100.

    UNTRUSTED BY DEFAULT, like the pairwise judge — experimental until it
    demonstrates agreement with human absolute grades.
    """
    from inspect_ai.model import get_model

    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    doc = DEFAULT_PRINCIPLES.read_text()
    doc_sha = hashlib.sha256(doc.encode()).hexdigest()[:16]
    system_prompt = (PROMPTS_DIR / "judge-grade.md").read_text()
    sections = _SECTION_RE.findall(doc)
    model = get_model(judge_model)

    results: dict = {}
    for label, module_dir in sorted(candidates.items()):
        module_text = render_module(module_dir)
        sample_scores = await asyncio.gather(
            *[_grade_once(model, system_prompt, doc, brief, module_text) for _ in range(samples)],
            return_exceptions=True,
        )
        per_section: dict = {}
        for section in sections:
            votes = [
                s[section]
                for s in sample_scores
                if isinstance(s, dict) and s.get(section) is not None
            ]
            per_section[section] = _median(votes) if votes else None
        applicable = [v for v in per_section.values() if v is not None]
        overall = round(sum(applicable) / len(applicable) / 4 * 100, 1) if applicable else None
        results[label] = {"overall": overall, "sections": per_section}

    summary = {
        "fixture": fixture_id,
        "mode": "absolute_grading",
        "judge_model": judge_model,
        "principles_sha256": doc_sha,
        "samples_per_candidate": samples,
        "status": "experimental (not calibrated against human absolute grades)",
        "grades": {label: r["overall"] for label, r in sorted(results.items(), key=lambda kv: -(kv[1]["overall"] or 0))},
        "detail": results,
    }
    (out_dir / "grades.json").write_text(json.dumps(summary, indent=2))
    return summary


def agreement(judgments_path: Path, human_path: Path) -> dict:
    """Judge-vs-human agreement on the pairs the human has ranked.

    Human file (yaml): pairs: [{a: label, b: label, winner: label}, ...]
    Judge verdict per pair = majority across recorded judgments.
    """
    judgments = [json.loads(line) for line in Path(judgments_path).read_text().splitlines() if line.strip()]
    human = yaml.safe_load(Path(human_path).read_text()) or {}
    results = []
    agree = 0
    graded = 0
    for pair in human.get("pairs", []):
        a, b, human_winner = pair["a"], pair["b"], pair.get("winner")
        if not human_winner:
            continue
        votes = [j["winner"] for j in judgments if {j["a"], j["b"]} == {a, b} and j["winner"]]
        if not votes:
            results.append({"pair": f"{a} vs {b}", "verdict": "no judgments"})
            continue
        counts = {label: votes.count(label) for label in set(votes)}
        top = max(counts.values())
        leaders = [label for label, c in counts.items() if c == top]
        graded += 1
        if len(leaders) > 1:
            # an order-split is a tie, not a majority — score it half credit
            agree += 0.5
            results.append({
                "pair": f"{a} vs {b}",
                "human": human_winner,
                "judge": f"TIE ({', '.join(f'{label}:{c}' for label, c in sorted(counts.items()))})",
                "agree": "tie",
            })
            continue
        judge_winner = leaders[0]
        ok = judge_winner == human_winner
        agree += ok
        results.append({
            "pair": f"{a} vs {b}",
            "human": human_winner,
            "judge": f"{judge_winner} ({counts[judge_winner]}/{len(votes)})",
            "agree": ok,
        })
    return {
        "graded_pairs": graded,
        "agreement": round(agree / graded, 3) if graded else None,
        "pairs": results,
    }
