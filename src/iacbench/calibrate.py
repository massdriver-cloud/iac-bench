"""Judge calibration: evidence-assisted human verdicts with adjudication.

The gold standard is the doctrine owner's verdict ON REFLECTION, not a blind
memory exercise. Three stages:

  packets    — pick informative pairs from the judge's own ranking (adjacent
               pairs + anchors), write one markdown packet per pair containing
               the brief, both modules, and each module's MECHANICAL findings
               (deterministic facts, not the thing being calibrated), plus a
               verdicts.yaml for the human to fill. Candidates appear under
               blind labels ("Module A"); the key is a separate file read
               only by the later stages. Judge verdicts are never shown at
               this stage. The packet run pins the doctrine edition
               and per-candidate module hashes into verdicts.yaml so verdicts
               can never silently drift from the artifacts they were made on.
  adjudicate — compare filled verdicts to the judge's majority per pair; for
               disagreements only, write adjudication.yaml with the judge's
               rationales. The human upholds (true disagreement) or revises
               ("I missed it" — counts toward the adjudicated number).
  finalize   — compute agreement and stamp scores.json AND grades.json.

Gate rules (the parts a hostile reader checks):
  - The only exclusions are HUMAN-declared ties ("too close to call"). The
    judge's own grades never remove a pair from the statistic — grade gaps are
    computed and DISCLOSED, nothing more.
  - The gate is RAW agreement; the adjudicated number is disclosed beside it.
    An upheld disagreement always counts against the judge.
  - A calibrated stamp requires at least MIN_DECISIVE_PAIRS counted pairs and
    refuses while any filled-out verdict set has unfilled entries.
  - The absolute grades (the composite's judged component) are gated in the
    same pass: for every counted pair, does the grade ordering agree with the
    human verdict? That rank-consistency, over the same floor, sets
    grades.json's status — the instrument that counts is the one certified.
"""

from __future__ import annotations

import json
import random
import string
from pathlib import Path

import yaml

_RATIONALE_CHARS = 1200
BLIND_KEY_FILE = "blind-key.yaml"
MIN_DECISIVE_PAIRS = 8
GATE = 0.8
NEAR_TIE_DISCLOSURE_GAP = 10.0  # disclosure only; never excludes


# ------------------------------------------------------------- pair selection

def select_pairs(bt_scores: dict, extra_anchors: int = 2) -> list:
    """Adjacent pairs in the judge's own ranking (where discrimination is
    hardest) plus far-apart anchor pairs. Which is which is not disclosed in
    the packets. Selection bias toward hard pairs is deliberate and DISCLOSED
    in the stamped result — agreement here is a stricter claim than agreement
    on random pairs."""
    ranked = list(bt_scores)  # bt_scores is already sorted best-first
    pairs = [(ranked[i], ranked[i + 1]) for i in range(len(ranked) - 1)]
    anchors = [(ranked[0], ranked[-1]), (ranked[1], ranked[-2])]
    for a, b in anchors[:extra_anchors]:
        if a != b and (a, b) not in pairs and (b, a) not in pairs:
            pairs.append((a, b))
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


def _blind_labels(fixture_id: str, shas: dict) -> dict:
    """real label -> "Module X". The shuffle is seeded by the fixture and the
    candidate snapshots, so it is reproducible but unrelated to model names."""
    labels = sorted(shas)
    rng = random.Random(f"{fixture_id}:" + ",".join(shas[k] for k in labels))
    rng.shuffle(labels)
    return {real: f"Module {string.ascii_uppercase[i]}" for i, real in enumerate(labels)}


def write_packets(fixture, candidates: dict, findings: dict, pairs: list, out_dir: Path) -> Path:
    """Packets and verdicts.yaml carry blind labels only ("Module A"); the
    mapping to real candidates lives in blind-key.yaml, read solely by the
    adjudicate and finalize stages. The human never sees which model wrote
    which module before every verdict is in."""
    from .artifacts import module_sha
    from .judge import DEFAULT_PRINCIPLES, principles_sha

    out_dir = Path(out_dir)
    pair_dir = out_dir / "pairs"
    pair_dir.mkdir(parents=True, exist_ok=True)
    shas = {label: module_sha(d) for label, d in candidates.items()}
    blind = _blind_labels(fixture.id, shas)
    entries = []
    for n, (real_a, real_b) in enumerate(pairs, 1):
        pair_id = f"pair-{n:02d}"
        a, b = blind[real_a], blind[real_b]
        body = [
            f"# {pair_id}: {a} vs {b}",
            "",
            "Question: **given the brief and the mechanical findings, which module",
            "would you rather inherit** — per docs/good-opentofu.md? Record your",
            f"verdict in verdicts.yaml under `{pair_id}`: a candidate label, or",
            "`tie` if the two are genuinely too close to call (ties are excluded",
            "from the statistic and disclosed — never guess to avoid a tie, and",
            "never tie to avoid a hard call).",
            "",
            "## Brief",
            "",
            fixture.brief.strip(),
            "",
            f"## Candidate: {a}",
            "",
            _findings_block(a, fixture, findings[real_a]),
            "",
            _module_block(a, candidates[real_a]),
            "",
            f"## Candidate: {b}",
            "",
            _findings_block(b, fixture, findings[real_b]),
            "",
            _module_block(b, candidates[real_b]),
        ]
        (pair_dir / f"{pair_id}.md").write_text("\n".join(body))
        entries.append({"id": pair_id, "a": a, "b": b, "winner": None, "note": ""})
    verdicts_path = out_dir / "verdicts.yaml"
    verdicts_path.write_text(
        "# Evidence-assisted calibration verdicts. For each pair, read the\n"
        "# packet in pairs/ and set winner to a candidate label, or 'tie'.\n"
        "# Fill this BEFORE any adjudication file exists; do not consult judge\n"
        "# outputs. Judge verdicts from memory of any module version other\n"
        "# than the packet sources are protocol violations — read the packet.\n"
        + yaml.safe_dump(
            {
                "fixture": fixture.id,
                "principles_sha256": principles_sha(DEFAULT_PRINCIPLES),
                "candidates": {blind[label]: sha for label, sha in sorted(shas.items(), key=lambda x: blind[x[0]])},
                "pairs": entries,
            },
            sort_keys=False,
        )
    )
    (out_dir / BLIND_KEY_FILE).write_text(
        "# Blind label -> real candidate. Do not open until every verdict is filled.\n"
        + yaml.safe_dump({blind[real]: real for real in sorted(blind, key=blind.get)}, sort_keys=False)
    )
    return verdicts_path


def _load_verdicts(verdicts_path: Path) -> dict:
    """verdicts.yaml with blind labels translated back to real candidates via
    the sibling blind-key.yaml (absent for unblinded legacy verdict sets)."""
    verdicts_path = Path(verdicts_path)
    verdicts = yaml.safe_load(verdicts_path.read_text())
    key_path = verdicts_path.parent / BLIND_KEY_FILE
    if not key_path.is_file():
        return verdicts
    key = yaml.safe_load(key_path.read_text())
    verdicts["candidates"] = {key.get(k, k): v for k, v in (verdicts.get("candidates") or {}).items()}
    for pair in verdicts["pairs"]:
        pair["a"] = key.get(pair["a"], pair["a"])
        pair["b"] = key.get(pair["b"], pair["b"])
        if pair.get("winner") and pair["winner"] != "tie":
            pair["winner"] = key.get(pair["winner"], pair["winner"])
    return verdicts


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


def _load_scores(judge_dir: Path) -> dict:
    return json.loads((Path(judge_dir) / "scores.json").read_text())


def _load_judgments(judge_dir: Path) -> list:
    """Judgments matching the current scores.json edition: same fixture,
    judge, prompt, doctrine — and, when the judgment carries artifact hashes,
    the same candidate snapshots."""
    scores = _load_scores(judge_dir)
    shas = scores.get("candidate_shas") or {}
    judgments = []
    for line in (Path(judge_dir) / "judgments.jsonl").read_text().splitlines():
        if not line.strip():
            continue
        j = json.loads(line)
        if (
            j.get("fixture") != scores.get("fixture")
            or j["prompt_sha256"] != scores["prompt_sha256"]
            or j["principles_sha256"] != scores["principles_sha256"]
            or j["judge_model"] != scores["judge_model"]
        ):
            continue
        # Legacy judgments lack shas; new ones must match the scored snapshots.
        for side, sha_key in (("a", "a_sha"), ("b", "b_sha")):
            expected = shas.get(j.get(side))
            if j.get(sha_key) is not None and expected is not None and j[sha_key] != expected:
                break
        else:
            judgments.append(j)
    return judgments


def _check_binding(verdicts: dict, judge_dir: Path) -> list:
    """Human verdicts and judge outputs must describe the same artifacts and
    doctrine edition. Returns a list of mismatch descriptions (empty = ok)."""
    problems = []
    scores = _load_scores(judge_dir)
    v_principles = verdicts.get("principles_sha256")
    if v_principles and scores.get("principles_sha256") != v_principles:
        problems.append(
            f"doctrine edition mismatch: verdicts {v_principles} vs judge {scores.get('principles_sha256')}"
        )
    v_shas = verdicts.get("candidates") or {}
    j_shas = scores.get("candidate_shas") or {}
    for label, sha in v_shas.items():
        if label in j_shas and j_shas[label] != sha:
            problems.append(f"candidate {label} snapshot mismatch: verdicts {sha} vs judge {j_shas[label]}")
    return problems


def adjudicate(verdicts_path: Path, judge_dir: Path, out_dir: Path) -> dict:
    verdicts = _load_verdicts(verdicts_path)
    binding = _check_binding(verdicts, judge_dir)
    if binding:
        return {"error": "artifact/edition binding mismatch", "problems": binding}
    judgments = _load_judgments(judge_dir)
    disagreements = []
    # Disjoint categories: a pair lands in exactly one bucket. A judge
    # order-split against a human verdict is a disagreement (reported with
    # its tie detail); human ties are exclusions.
    summary = {"agree": 0, "disagree": 0, "human_tie": 0, "unfilled": 0}
    for pair in verdicts["pairs"]:
        human = pair.get("winner")
        if not human:
            summary["unfilled"] += 1
            continue
        if str(human).lower() == "tie":
            summary["human_tie"] += 1
            continue
        judge_winner, votes, rationales = _judge_majority(judgments, pair["a"], pair["b"])
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
            # uphold: false -> the judge caught something real and
            #                  doctrine-grounded; cite the doctrine section
            "uphold": None,
            "reason": "",
            "doctrine_section": "",
        })
    out_path = Path(out_dir) / "adjudication.yaml"
    out_path.write_text(
        "# Disagreements only. For each: read the judge's rationales, then set\n"
        "# uphold: true (your verdict stands — real disagreement) or\n"
        "# uphold: false (the judge caught something real that you missed).\n"
        "# A reversal (uphold: false) MUST name the doctrine_section that\n"
        "# grounds it; a rationale that is vibes rather than evidence must be\n"
        "# upheld against. NOTE: the gate is computed on RAW agreement — a\n"
        "# reversal improves only the disclosed adjudicated number, so there\n"
        "# is nothing to gain by reversing.\n"
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
) -> dict:
    verdicts = _load_verdicts(verdicts_path)
    binding = _check_binding(verdicts, judge_dir)
    if binding:
        return {"error": "artifact/edition binding mismatch", "problems": binding}
    adjudication = yaml.safe_load(Path(adjudication_path).read_text())
    judgments = _load_judgments(judge_dir)
    resolved = {d["id"]: d for d in adjudication.get("disagreements", [])}

    grades: dict = {}
    grades_path = Path(judge_dir) / "grades.json"
    if grades_path.is_file():
        data = json.loads(grades_path.read_text())
        grades = {k: v for k, v in (data.get("grades") or {}).items() if v is not None}

    unfilled = [p["id"] for p in verdicts["pairs"] if not p.get("winner")]
    unresolved = [d["id"] for d in adjudication.get("disagreements", []) if d.get("uphold") is None]

    def tally(pairs: list) -> dict:
        graded = agree_raw = agree_adj = grade_consistent = grade_pairs = 0
        near_ties: list = []
        for pair in pairs:
            human = pair.get("winner")
            if not human or str(human).lower() == "tie":
                continue
            judge_winner, _, _ = _judge_majority(judgments, pair["a"], pair["b"])
            graded += 1
            ga, gb = grades.get(pair["a"]), grades.get(pair["b"])
            if ga is not None and gb is not None:
                grade_pairs += 1
                if abs(ga - gb) < NEAR_TIE_DISCLOSURE_GAP:
                    near_ties.append(pair["id"])  # disclosure only — still counted
                grade_winner = pair["a"] if ga > gb else pair["b"]
                grade_consistent += grade_winner == human
            if judge_winner == human:
                agree_raw += 1
                agree_adj += 1
                continue
            d = resolved.get(pair["id"])
            if d is not None and d.get("uphold") is False:
                agree_adj += 1  # revised on reflection — disclosed, never gated on
        return {
            "graded_pairs": graded,
            "raw_agreement": round(agree_raw / graded, 3) if graded else None,
            "adjudicated_agreement": round(agree_adj / graded, 3) if graded else None,
            "grade_rank_consistency": round(grade_consistent / grade_pairs, 3) if grade_pairs else None,
            "grade_pairs": grade_pairs,
            "near_tie_pairs_disclosed": near_ties,
        }

    all_pairs = verdicts["pairs"]
    overall = tally(all_pairs)
    result = {
        "fixture": verdicts["fixture"],
        "method": (
            "evidence-assisted verdicts; hard-pair-biased selection (adjacent by judge "
            "ranking); exclusions are human ties only; gate = raw agreement"
        ),
        "overall": overall,
        "models_only": tally([p for p in all_pairs if not _is_ref_pair(p)]),
        "human_ties": [p["id"] for p in all_pairs if str(p.get("winner")).lower() == "tie"],
        "unfilled": unfilled,
        "unresolved_disagreements": unresolved,
    }
    if unfilled or unresolved:
        result["error"] = "refusing to stamp: unfilled verdicts or unresolved adjudications remain"
        return result

    raw = overall["raw_agreement"]
    enough = overall["graded_pairs"] >= MIN_DECISIVE_PAIRS
    pairwise_status = (
        "calibrated (raw agreement, hard-pair sample)"
        if enough and raw is not None and raw >= GATE
        else (
            f"experimental (needs >= {MIN_DECISIVE_PAIRS} counted pairs)"
            if not enough else "experimental (failed calibration)"
        )
    )
    scores_path = Path(judge_dir) / "scores.json"
    scores = _load_scores(judge_dir)
    scores["calibration"] = result
    scores["agreement"] = raw
    scores["graded_pairs"] = overall["graded_pairs"]
    scores["status"] = pairwise_status
    scores_path.write_text(json.dumps(scores, indent=2))
    result["pairwise_status"] = pairwise_status

    # The composite's judged component is the ABSOLUTE grade — certify it
    # against the same human verdicts (rank consistency), same floor.
    if grades_path.is_file():
        consistency = overall["grade_rank_consistency"]
        enough_g = overall["grade_pairs"] >= MIN_DECISIVE_PAIRS
        grade_status = (
            "calibrated (rank-consistent with human verdicts)"
            if enough_g and consistency is not None and consistency >= GATE
            else (
                f"experimental (needs >= {MIN_DECISIVE_PAIRS} graded pairs)"
                if not enough_g else "experimental (failed calibration)"
            )
        )
        data = json.loads(grades_path.read_text())
        data["agreement"] = consistency
        data["agreement_method"] = "rank consistency vs human pairwise verdicts"
        data["graded_pairs"] = overall["grade_pairs"]
        data["status"] = grade_status
        grades_path.write_text(json.dumps(data, indent=2))
        result["grades_status"] = grade_status
    return result
