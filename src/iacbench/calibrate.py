"""Judge calibration: human pairwise verdicts vs the judge's absolute grades.

The judged component of the composite is the judge's 0-100 grade on the
doctrine sections the rubric does not score. People are far more consistent
choosing between two modules than assigning numbers, so the human answers
pairs and the judge is checked on whether its grades order each pair the same
way. Three stages:

  packets    — write one markdown packet per pair: the question, the graded
               doctrine sections, the brief, and both modules with their
               MECHANICAL findings shown as settled context. Candidates
               appear under blind labels ("Module A"); the key is a separate
               file read only by the later stages. Judge grades are never
               shown at this stage. verdicts.yaml pins the doctrine edition
               and per-candidate module hashes so verdicts can never silently
               drift from the artifacts they were made on.
  adjudicate — per judge: for pairs where the grades order the modules
               against the human verdict, write that judge's section grades
               and evidence. Optional: the human may mark a miss "revised"
               ("the judge saw something I missed"), which counts only
               toward a disclosed adjudicated number.
  finalize   — per judge: compute agreement and stamp grades.json.

Gate rules (the parts a hostile reader checks):
  - Agreement = share of decided human verdicts where the judge grades the
    human's pick strictly higher. Equal grades are a miss.
  - The only exclusions are HUMAN-declared ties ("too close to call").
  - The gate is RAW agreement; the adjudicated number is disclosed beside it.
  - A calibrated stamp requires at least MIN_DECISIVE_PAIRS counted pairs and
    refuses while any verdict is unfilled.
"""

from __future__ import annotations

import json
import random
import string
from pathlib import Path

import yaml

_EVIDENCE_CHARS = 400
BLIND_KEY_FILE = "blind-key.yaml"
MIN_DECISIVE_PAIRS = 8
GATE = 0.8


# ------------------------------------------------------------- pair selection

def select_pairs(ranking: dict, extra_anchors: int = 2) -> list:
    """Adjacent pairs in a best-first ranking (where discrimination is
    hardest) plus far-apart anchor pairs. Selection bias toward hard pairs is
    deliberate and disclosed — agreement here is a stricter claim than
    agreement on random pairs."""
    ranked = list(ranking)
    pairs = [(ranked[i], ranked[i + 1]) for i in range(len(ranked) - 1)]
    anchors = [(ranked[0], ranked[-1]), (ranked[1], ranked[-2])]
    for a, b in anchors[:extra_anchors]:
        if a != b and (a, b) not in pairs and (b, a) not in pairs:
            pairs.append((a, b))
    return sorted(tuple(sorted(p)) for p in pairs)


def pairs_from_verdicts(verdicts_path: Path) -> list:
    """The real-candidate pairs of an earlier verdict set, so a re-asked
    question reuses modules the human has already read."""
    return [tuple(sorted((p["a"], p["b"]))) for p in _load_verdicts(verdicts_path)["pairs"]]


# ------------------------------------------------------------- packet writing

def _question(pair_id: str, sections: list) -> list:
    return [
        "## What you are deciding",
        "",
        "The rubric has already scored correctness: the mechanical findings under",
        "each module are settled facts and are scored elsewhere. **Do not let them",
        "decide your pick.** Judge only how well each module is written and",
        "designed, on these sections of docs/good-opentofu.md:",
        "",
        *[f"- {s}" for s in sections],
        "",
        "Pick the module you would rather maintain on those grounds alone. Record",
        f"the label in verdicts.yaml under `{pair_id}`, or `tie` only if the two",
        "truly cannot be separated on those grounds (ties are excluded from the",
        "statistic and disclosed).",
    ]


def _findings_block(label: str, fixture, result) -> str:
    lines = [
        f"### Already scored by the rubric — {label}",
        "",
        "Context only. These results are counted in the mechanical score; do not",
        "weigh them again.",
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
    from .judge import DEFAULT_PRINCIPLES, graded_sections, principles_sha

    sections = graded_sections(DEFAULT_PRINCIPLES.read_text())

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
            *_question(pair_id, sections),
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
        "# Calibration verdicts. For each pair, read the packet in pairs/ and\n"
        "# set winner to the module you would rather maintain on the listed\n"
        "# doctrine sections alone, or 'tie'. Fill this before any adjudication\n"
        "# file exists; do not consult judge outputs.\n"
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


# ------------------------------------------------------------- judge grades

def _load_grades(judge_dir: Path) -> dict:
    return json.loads((Path(judge_dir) / "grades.json").read_text())


def _check_binding(verdicts: dict, grades: dict) -> list:
    """Human verdicts and judge grades must describe the same artifacts and
    doctrine edition. Returns a list of mismatch descriptions (empty = ok)."""
    problems = []
    v_principles = verdicts.get("principles_sha256")
    if v_principles and grades.get("principles_sha256") != v_principles:
        problems.append(
            f"doctrine edition mismatch: verdicts {v_principles} vs judge {grades.get('principles_sha256')}"
        )
    detail = grades.get("detail") or {}
    for label, sha in (verdicts.get("candidates") or {}).items():
        judged = (detail.get(label) or {}).get("module_sha")
        if judged is not None and judged != sha:
            problems.append(f"candidate {label} snapshot mismatch: verdicts {sha} vs judge {judged}")
    return problems


def _grade_pick(grades: dict, a: str, b: str) -> str | None:
    """The module the judge grades strictly higher; None for equal or missing."""
    overall = {k: (v or {}).get("overall") for k, v in (grades.get("detail") or {}).items()}
    ga, gb = overall.get(a), overall.get(b)
    if ga is None or gb is None or ga == gb:
        return None
    return a if ga > gb else b


def adjudication_path(out_dir: Path, judge_dir: Path) -> Path:
    return Path(out_dir) / f"adjudication-{Path(judge_dir).name}.yaml"


# ------------------------------------------------------------- adjudication

def _section_contrast(grades: dict, a: str, b: str) -> dict:
    """Per graded section where the two modules' grades differ: both grades
    and the judge's evidence — what the judge actually weighed."""
    detail = grades.get("detail") or {}
    da, db = detail.get(a) or {}, detail.get(b) or {}
    contrast = {}
    for section, ga in (da.get("sections") or {}).items():
        gb = (db.get("sections") or {}).get(section)
        if ga == gb:
            continue
        contrast[section] = {
            a: {"grade": ga, "evidence": [e[:_EVIDENCE_CHARS] for e in (da.get("evidence") or {}).get(section, [])]},
            b: {"grade": gb, "evidence": [e[:_EVIDENCE_CHARS] for e in (db.get("evidence") or {}).get(section, [])]},
        }
    return contrast


def adjudicate(verdicts_path: Path, judge_dir: Path, out_dir: Path) -> dict:
    verdicts = _load_verdicts(verdicts_path)
    grades = _load_grades(judge_dir)
    binding = _check_binding(verdicts, grades)
    if binding:
        return {"error": "artifact/edition binding mismatch", "problems": binding}
    overall = {k: (v or {}).get("overall") for k, v in (grades.get("detail") or {}).items()}
    misses = []
    summary = {"agree": 0, "miss": 0, "human_tie": 0, "unfilled": 0}
    for pair in verdicts["pairs"]:
        human = pair.get("winner")
        if not human:
            summary["unfilled"] += 1
            continue
        if str(human).lower() == "tie":
            summary["human_tie"] += 1
            continue
        if _grade_pick(grades, pair["a"], pair["b"]) == human:
            summary["agree"] += 1
            continue
        summary["miss"] += 1
        misses.append({
            "id": pair["id"],
            "human": human,
            "human_note": pair.get("note", ""),
            "grades": {pair["a"]: overall.get(pair["a"]), pair["b"]: overall.get(pair["b"])},
            "differing_sections": _section_contrast(grades, pair["a"], pair["b"]),
            # Optional. revised: true -> the judge saw something real that you
            # missed; name the doctrine_section. Leave blank to stand by your pick.
            "revised": None,
            "doctrine_section": "",
        })
    out_path = adjudication_path(out_dir, judge_dir)
    out_path.write_text(
        f"# Judge: {grades.get('judge_model')}. Pairs where this judge's grades order\n"
        "# the modules against your pick. Optional review: if the judge's evidence\n"
        "# shows something real you missed, set revised: true and name the\n"
        "# doctrine_section. The gate uses your original picks either way; a\n"
        "# revision only changes the disclosed adjudicated number.\n"
        + yaml.safe_dump({"fixture": verdicts["fixture"], "misses": misses}, sort_keys=False, allow_unicode=True)
    )
    return {**summary, "adjudication": str(out_path)}


# ------------------------------------------------------------- finalize

def _is_ref_pair(pair: dict) -> bool:
    return any(str(pair[k]).startswith("ref") for k in ("a", "b"))


def finalize(verdicts_path: Path, judge_dir: Path, out_dir: Path) -> dict:
    verdicts = _load_verdicts(verdicts_path)
    grades = _load_grades(judge_dir)
    binding = _check_binding(verdicts, grades)
    if binding:
        return {"error": "artifact/edition binding mismatch", "problems": binding}
    adj_path = adjudication_path(out_dir, judge_dir)
    adjudication = yaml.safe_load(adj_path.read_text()) if adj_path.is_file() else {}
    revised = {m["id"] for m in (adjudication or {}).get("misses", []) if m.get("revised") is True}
    unfilled = [p["id"] for p in verdicts["pairs"] if not p.get("winner")]

    def tally(pairs: list) -> dict:
        counted = agree_raw = agree_adj = 0
        for pair in pairs:
            human = pair.get("winner")
            if not human or str(human).lower() == "tie":
                continue
            counted += 1
            if _grade_pick(grades, pair["a"], pair["b"]) == human:
                agree_raw += 1
                agree_adj += 1
            elif pair["id"] in revised:
                agree_adj += 1  # revised on reflection — disclosed, never gated on
        return {
            "counted_pairs": counted,
            "raw_agreement": round(agree_raw / counted, 3) if counted else None,
            "adjudicated_agreement": round(agree_adj / counted, 3) if counted else None,
        }

    all_pairs = verdicts["pairs"]
    overall = tally(all_pairs)
    result = {
        "fixture": verdicts["fixture"],
        "judge_model": grades.get("judge_model"),
        "method": (
            "human pairwise verdicts vs judge grade order on the judge-graded doctrine "
            "sections; hard-pair-biased selection; exclusions are human ties only; "
            "equal grades count as misses; gate = raw agreement"
        ),
        "overall": overall,
        "models_only": tally([p for p in all_pairs if not _is_ref_pair(p)]),
        "human_ties": [p["id"] for p in all_pairs if str(p.get("winner")).lower() == "tie"],
        "unfilled": unfilled,
    }
    if unfilled:
        result["error"] = "refusing to stamp: unfilled verdicts remain"
        return result

    raw = overall["raw_agreement"]
    enough = overall["counted_pairs"] >= MIN_DECISIVE_PAIRS
    status = (
        "calibrated (grade order agrees with human verdicts)"
        if enough and raw is not None and raw >= GATE
        else (
            f"experimental (needs >= {MIN_DECISIVE_PAIRS} counted pairs)"
            if not enough else "experimental (failed calibration)"
        )
    )
    grades["calibration"] = result
    grades["agreement"] = raw
    grades["agreement_method"] = "grade order vs human pairwise verdicts"
    grades["graded_pairs"] = overall["counted_pairs"]
    grades["status"] = status
    (Path(judge_dir) / "grades.json").write_text(json.dumps(grades, indent=2))
    result["status"] = status
    return result
