"""Judge calibration: evidence-assisted human verdicts with adjudication.

The gold standard is the doctrine owner's verdict ON REFLECTION, not a blind
memory exercise. Three stages:

  packets    — pick informative pairs from the judge's own ranking (adjacent
               pairs + anchors), write one markdown packet per pair containing
               the brief, both modules, and each module's MECHANICAL findings
               (deterministic facts, not the thing being calibrated), plus a
               verdicts.yaml for the human to fill. Judge verdicts are never
               shown at this stage.
  adjudicate — compare filled verdicts to the judge's majority per pair; for
               disagreements only, write adjudication.yaml with the judge's
               rationales. The human upholds (true disagreement) or revises
               ("I missed it" — counts as agreement, usually a doctrine edit).
  finalize   — compute raw and adjudicated agreement (overall, and excluding
               pairs that contain the owner's own reference modules), stamp
               scores.json. Human ties are excluded from the statistic and
               reported.
"""

from __future__ import annotations

import json
from pathlib import Path

import yaml

_RATIONALE_CHARS = 1200


# ------------------------------------------------------------- pair selection

def select_pairs(bt_scores: dict, extra_anchors: int = 2) -> list:
    """Adjacent pairs in the judge's own ranking (where discrimination is
    hardest and calibration is most informative) plus far-apart anchor pairs
    as sanity checks. Which is which is not disclosed in the packets."""
    ranked = list(bt_scores)  # bt_scores is already sorted best-first
    pairs = [(ranked[i], ranked[i + 1]) for i in range(len(ranked) - 1)]
    anchors = [(ranked[0], ranked[-1]), (ranked[1], ranked[-2])]
    for a, b in anchors[:extra_anchors]:
        if a != b and (a, b) not in pairs and (b, a) not in pairs:
            pairs.append((a, b))
    # deterministic, ranking-agnostic presentation order
    return sorted(tuple(sorted(p)) for p in pairs)


# ------------------------------------------------------------- packet writing

def _findings_block(label: str, fixture, result) -> str:
    lines = [
        f"### Mechanical findings — {label}",
        "",
        "These are deterministic facts from the rubric engine, provided so the",
        "verdict does not depend on spotting every defect by eye. The judged",
        "layer's question is the residual: given these facts, which *design*",
        "is better?",
        "",
        f"- gate: {'pass' if result.gate else 'FAIL'} · rubric score: "
        f"{result.semantic_score} · mandatory failures: "
        f"{', '.join(result.mandatory_failures) or 'none'}",
        "",
        "| rubric item | result | description |",
        "|---|---|---|",
    ]
    desc = {i["id"]: " ".join(i["description"].split()) for i in fixture.items}
    for item_id, value in result.items.items():
        mark = "✓" if float(value) >= 1.0 else ("½" if float(value) > 0 else "✗")
        lines.append(f"| {item_id} | {mark} | {desc.get(item_id, '')} |")
    if result.expertise:
        lines += ["", "| expertise item | present |", "|---|---|"]
        for item_id, present in result.expertise.items():
            lines.append(f"| {item_id} | {'✓' if present else '—'} |")
    warnings = [d for d in result.details if d.startswith(("sweep:", "static lens:"))]
    if warnings:
        lines += ["", "Blind-spot warnings:"] + [f"- {w}" for w in warnings]
    return "\n".join(lines)


def _module_block(label: str, module_dir: Path) -> str:
    from .judge import render_module

    return f"### Source — {label}\n\n{render_module(module_dir)}"


def write_packets(fixture, candidates: dict, findings: dict, pairs: list, out_dir: Path) -> Path:
    out_dir = Path(out_dir)
    pair_dir = out_dir / "pairs"
    pair_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for n, (a, b) in enumerate(pairs, 1):
        pair_id = f"pair-{n:02d}"
        body = [
            f"# {pair_id}: {a} vs {b}",
            "",
            "Question: **given the brief and the mechanical findings, which module",
            "would you rather inherit** — per docs/good-opentofu.md? Record your",
            f"verdict in verdicts.yaml under `{pair_id}` (a label, or `tie`).",
            "",
            "## Brief",
            "",
            fixture.brief.strip(),
            "",
            f"## Candidate: {a}",
            "",
            _findings_block(a, fixture, findings[a]),
            "",
            _module_block(a, candidates[a]),
            "",
            f"## Candidate: {b}",
            "",
            _findings_block(b, fixture, findings[b]),
            "",
            _module_block(b, candidates[b]),
        ]
        (pair_dir / f"{pair_id}-{a}-vs-{b}.md").write_text("\n".join(body))
        entries.append({"id": pair_id, "a": a, "b": b, "winner": None, "note": ""})
    verdicts_path = out_dir / "verdicts.yaml"
    verdicts_path.write_text(
        "# Evidence-assisted calibration verdicts. For each pair, read the\n"
        "# packet in pairs/ and set winner to a candidate label, or 'tie'.\n"
        "# Fill this BEFORE any adjudication file exists; do not consult judge\n"
        "# outputs. Notes are optional but make adjudication faster.\n"
        + yaml.safe_dump({"fixture": fixture.id, "pairs": entries}, sort_keys=False)
    )
    return verdicts_path


# ------------------------------------------------------------- adjudication

def _judge_majority(judgments: list, a: str, b: str) -> tuple:
    """(winner|None, votes dict, rationales) for one pair. None = order-split tie."""
    votes: dict = {}
    rationales: list = []
    for j in judgments:
        if {j["a"], j["b"]} != {a, b} or not j["winner"]:
            continue
        votes[j["winner"]] = votes.get(j["winner"], 0) + 1
        rationales.append(f"[verdict: {j['winner']}] {j['rationale'][:_RATIONALE_CHARS]}")
    if not votes:
        return None, votes, rationales
    top = max(votes.values())
    leaders = [label for label, c in votes.items() if c == top]
    return (leaders[0] if len(leaders) == 1 else None), votes, rationales


def _load_judgments(judge_dir: Path) -> list:
    scores = json.loads((Path(judge_dir) / "scores.json").read_text())
    judgments = []
    for line in (Path(judge_dir) / "judgments.jsonl").read_text().splitlines():
        if not line.strip():
            continue
        j = json.loads(line)
        if (
            j["prompt_sha256"] == scores["prompt_sha256"]
            and j["principles_sha256"] == scores["principles_sha256"]
            and j["judge_model"] == scores["judge_model"]
        ):
            judgments.append(j)
    return judgments


def adjudicate(verdicts_path: Path, judge_dir: Path, out_dir: Path) -> dict:
    verdicts = yaml.safe_load(Path(verdicts_path).read_text())
    judgments = _load_judgments(judge_dir)
    disagreements = []
    summary = {"agree": 0, "disagree": 0, "human_tie": 0, "judge_tie": 0, "unfilled": 0}
    for pair in verdicts["pairs"]:
        human = pair.get("winner")
        if not human:
            summary["unfilled"] += 1
            continue
        judge_winner, votes, rationales = _judge_majority(judgments, pair["a"], pair["b"])
        if str(human).lower() == "tie":
            summary["human_tie"] += 1
            continue
        if judge_winner is None:
            # judge order-split against a human verdict: disagreement by rule
            summary["judge_tie"] += 1
        if judge_winner == human:
            summary["agree"] += 1
            continue
        summary["disagree"] += 1
        disagreements.append({
            "id": pair["id"],
            "a": pair["a"],
            "b": pair["b"],
            "human": human,
            "human_note": pair.get("note", ""),
            "judge": judge_winner or f"TIE {votes}",
            "judge_rationales": rationales,
            # uphold: true  -> real disagreement, counts against the judge
            # uphold: false -> "I missed it" — counts as agreement; say why
            "uphold": None,
            "reason": "",
        })
    out_path = Path(out_dir) / "adjudication.yaml"
    out_path.write_text(
        "# Disagreements only. For each: read the judge's rationales, then set\n"
        "# uphold: true (your verdict stands — real disagreement) or\n"
        "# uphold: false (the judge caught something real and doctrine-grounded\n"
        "# that you missed — counts as agreement). 'reason' is required either\n"
        "# way; a rationale that is vibes rather than evidence must be upheld\n"
        "# against.\n"
        + yaml.safe_dump({"fixture": verdicts["fixture"], "disagreements": disagreements}, sort_keys=False)
    )
    return {**summary, "adjudication": str(out_path)}


# ------------------------------------------------------------- finalize

def _is_ref_pair(pair: dict) -> bool:
    return any(str(pair[k]).startswith("ref") for k in ("a", "b"))


def finalize(
    verdicts_path: Path,
    adjudication_path: Path,
    judge_dir: Path,
    near_tie_gap: float = 10.0,
) -> dict:
    verdicts = yaml.safe_load(Path(verdicts_path).read_text())
    adjudication = yaml.safe_load(Path(adjudication_path).read_text())
    judgments = _load_judgments(judge_dir)
    resolved = {d["id"]: d for d in adjudication.get("disagreements", [])}

    # Near-tie exclusion: pairs whose absolute grades sit within near_tie_gap
    # of each other are preference territory — which way they fall says nothing
    # about the judge's fitness, so they are excluded from the gate statistic
    # and disclosed. Applies only when grades exist for both candidates.
    grades: dict = {}
    grades_path = Path(judge_dir) / "grades.json"
    if grades_path.is_file():
        data = json.loads(grades_path.read_text())
        grades = {k: v for k, v in (data.get("grades") or {}).items() if v is not None}

    def decisive(pair: dict) -> bool:
        ga, gb = grades.get(pair["a"]), grades.get(pair["b"])
        if ga is None or gb is None:
            return True
        return abs(ga - gb) >= near_tie_gap

    near_ties = [p["id"] for p in verdicts["pairs"] if p.get("winner") and not decisive(p)]

    def tally(pairs: list) -> dict:
        graded = agree_raw = agree_adj = 0
        for pair in pairs:
            human = pair.get("winner")
            if not human or str(human).lower() == "tie" or not decisive(pair):
                continue
            judge_winner, _, _ = _judge_majority(judgments, pair["a"], pair["b"])
            graded += 1
            if judge_winner == human:
                agree_raw += 1
                agree_adj += 1
                continue
            d = resolved.get(pair["id"])
            if d is not None and d.get("uphold") is False:
                agree_adj += 1  # revised on reflection: the judge was right
        return {
            "graded_pairs": graded,
            "raw_agreement": round(agree_raw / graded, 3) if graded else None,
            "adjudicated_agreement": round(agree_adj / graded, 3) if graded else None,
        }

    all_pairs = verdicts["pairs"]
    result = {
        "fixture": verdicts["fixture"],
        "method": "evidence-assisted verdicts with adjudication; "
                  f"near-tie pairs (grade gap < {near_tie_gap:g}) excluded",
        "overall": tally(all_pairs),
        "models_only": tally([p for p in all_pairs if not _is_ref_pair(p)]),
        "near_tie_excluded": near_ties,
        "unresolved_disagreements": [
            d["id"] for d in adjudication.get("disagreements", []) if d.get("uphold") is None
        ],
    }
    if result["unresolved_disagreements"]:
        return result

    scores_path = Path(judge_dir) / "scores.json"
    scores = json.loads(scores_path.read_text())
    adj = result["overall"]["adjudicated_agreement"]
    scores["calibration"] = result
    scores["agreement"] = adj
    scores["graded_pairs"] = result["overall"]["graded_pairs"]
    scores["status"] = (
        "calibrated (adjudicated)" if adj is not None and adj >= 0.8
        else "experimental (failed calibration)"
    )
    scores_path.write_text(json.dumps(scores, indent=2))
    result["status"] = scores["status"]
    return result
