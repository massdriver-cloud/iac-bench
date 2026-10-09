"""Judge calibration: the doctrine owner checks the judges' section grades.

The judged component of the composite is a judge's 0-2 grade per doctrine
section (the sections the rubric does not score), rolled up to 0-100. The
cheapest reliable human check of that is per cell: for one module and one
section, is the grade right? Two stages:

  sheets   — one review sheet per module under blind labels ("Module A"):
             a table of every graded section with each judge's grade and
             evidence side by side, then the module source. The human records
             their OWN grade (0, 1 or 2) per cell in review.yaml — not
             agree/disagree, so seeing two judges cannot collapse into
             nodding along, and a miss records how far off the judge was.
             review.yaml pins the doctrine edition and per-candidate module
             hashes so a review can never silently drift from its artifacts.
             After a doctrine revision, an earlier review can prefill the
             human's grades (matched by candidate and section heading); rows
             where a judge now differs are flagged, so only those need a look.
             A renamed section starts blank.
  finalize — per judge: exact agreement between the judge's grade and the
             human's, overall and per section; stamps grades.json.

Gate rules (the parts a hostile reader checks):
  - Agreement = share of cells where the judge's grade equals the human's
    exactly.
  - A calibrated stamp requires at least MIN_CELLS cells, agreement >= GATE
    in EVERY section, and refuses while any cell is unfilled. The gate is per
    section because sections every module aces would otherwise carry a judge
    that gets the discriminating sections wrong. A section that keeps failing
    is reworded or dropped from the judged component.
"""

from __future__ import annotations

import json
import random
import string
from pathlib import Path

import yaml

BLIND_KEY_FILE = "blind-key.yaml"
REVIEW_FILE = "review.yaml"
MIN_CELLS = 40
GATE = 0.75
_EVIDENCE_CHARS = 300


def _blind_labels(salt: str, shas: dict) -> dict:
    """real label -> "Module X". Seeded by a per-review salt and the
    candidate snapshots: reproducible, unrelated to model names, and
    different from any earlier review of the same modules."""
    labels = sorted(shas)
    rng = random.Random(f"{salt}:" + ",".join(shas[k] for k in labels))
    rng.shuffle(labels)
    return {real: f"Module {string.ascii_uppercase[i]}" for i, real in enumerate(labels)}


def _load_grades(judge_dir: Path) -> dict:
    return json.loads((Path(judge_dir) / "grades.json").read_text())


def _cell(grades: dict, label: str, section: str) -> tuple:
    """(grade, evidence) for one judge, module and section. The evidence is
    from a sample that gave the median grade, so the sentence explains the
    grade shown."""
    detail = (grades.get("detail") or {}).get(label) or {}
    grade = (detail.get("sections") or {}).get(section)
    samples = (detail.get("evidence") or {}).get(section) or []
    shown = "NA" if grade is None else (int(grade) if float(grade).is_integer() else grade)
    tag = f"[{shown}]"
    evidence = next((e for e in samples if e.startswith(tag)), samples[0] if samples else "")
    if evidence.startswith(tag):
        evidence = evidence[len(tag):]
    return shown, " ".join(evidence.split())[:_EVIDENCE_CHARS]


def _judge_name(grades: dict) -> str:
    return grades.get("judge_model", "?").split("/")[-1]


def _binding_problems(doc_sha: str | None, shas: dict, grades: dict) -> list:
    """The review and a judge's grades must describe the same doctrine
    edition and module snapshots."""
    problems = []
    if doc_sha and grades.get("principles_sha256") != doc_sha:
        problems.append(f"doctrine edition mismatch: review {doc_sha} vs judge {grades.get('principles_sha256')}")
    detail = grades.get("detail") or {}
    for label, sha in shas.items():
        judged = (detail.get(label) or {}).get("module_sha")
        if judged is None:
            problems.append(f"candidate {label} was not graded by this judge")
        elif judged != sha:
            problems.append(f"candidate {label} snapshot mismatch: review {sha} vs judge {judged}")
    return problems


def write_sheets(fixture, candidates: dict, judge_dirs: list, out_dir: Path, prefill: Path | None = None) -> Path:
    """Review sheets (modules/Module-X.md) plus review.yaml to fill. Every
    judge must have graded the current doctrine edition and these exact
    module snapshots. `prefill` is an earlier review directory whose grades
    seed this one for the candidates whose snapshots are unchanged."""
    from .artifacts import module_sha
    from .judge import (
        DEFAULT_PRINCIPLES,
        graded_sections,
        principles_sha,
        render_module,
    )

    out_dir = Path(out_dir)
    sheet_dir = out_dir / "modules"
    sheet_dir.mkdir(parents=True, exist_ok=True)
    sections = graded_sections(DEFAULT_PRINCIPLES.read_text())
    doc_sha = principles_sha(DEFAULT_PRINCIPLES)
    shas = {label: module_sha(d) for label, d in candidates.items()}
    judges = [_load_grades(d) for d in judge_dirs]
    for judge in judges:
        problems = _binding_problems(doc_sha, shas, judge)
        if problems:
            raise ValueError(f"{_judge_name(judge)}: " + "; ".join(problems))
    blind = _blind_labels(out_dir.name, shas)
    ordered = sorted(blind, key=blind.get)
    previous: dict = {}
    if prefill:
        earlier = _load_review(prefill)
        previous = {
            real: {s: _norm(g) for s, g in row.items() if s in sections}
            for real, row in earlier["grades"].items()
            if earlier["candidates"].get(real) == shas.get(real)
        }

    for real in ordered:
        label = blind[real]
        rows = []
        for section in sections:
            cells = [_cell(j, real, section) for j in judges]
            grades_txt = " | ".join(str(g) for g, _ in cells)
            evidence = "<br>".join(f"**{_judge_name(j)}:** {e}" for j, (_, e) in zip(judges, cells, strict=True))
            if prefill:
                yours = previous.get(real, {}).get(section)
                flag = "blank" if yours is None else ("⚠ check" if any(g != yours for g, _ in cells) else "")
                rows.append(f"| {section} | {'' if yours is None else yours} | {flag} | {grades_txt} | {evidence} |")
            else:
                rows.append(f"| {section} | {grades_txt} | {evidence} |")
        if prefill:
            header = "| Section | Yours | Check | " + " | ".join(_judge_name(j) for j in judges) + " | Evidence |"
            rule = "|---|---|---|" + "---|" * len(judges) + "---|"
            intro = [
                "Your grades from the previous review are filled in. Look at rows",
                "marked **⚠ check** (a judge now differs from you) and **blank** (a new or",
                "renamed section); change a grade only if you now see it differently.",
                "",
            ]
        else:
            header = "| Section | " + " | ".join(_judge_name(j) for j in judges) + " | Evidence |"
            rule = "|---|" + "---|" * len(judges) + "---|"
            intro = []
        body = [
            f"# {label}",
            "",
            "## What you are doing",
            "",
            "For each doctrine section below, record **your own grade** for this",
            f"module in {REVIEW_FILE} under `{label}`: 0 (no credit), 1 (partial",
            "credit) or 2 (full credit). A section with nothing in the module to",
            "apply to has nothing to fault and earns 2. The judges' grades and evidence are there to speed you up;",
            "agree with them or not. Grade only these sections: security,",
            "tagging, provider configuration, versions, destructive defaults and",
            "scope invention are scored by the rubric and are not part of this review.",
            "",
            "## Judges' grades",
            "",
            *intro,
            header,
            rule,
            *rows,
            "",
            "## Brief",
            "",
            fixture.brief.strip(),
            "",
            "## Source",
            "",
            render_module(candidates[real]),
        ]
        (sheet_dir / f"{label.replace(' ', '-')}.md").write_text("\n".join(body))

    review_path = out_dir / REVIEW_FILE
    review_path.write_text(
        "# Your grade per module and doctrine section: 0, 1 or 2.\n"
        "# Read modules/Module-X.md for the source and the judges' grades.\n"
        + yaml.safe_dump(
            {
                "fixture": fixture.id,
                "principles_sha256": doc_sha,
                "candidates": {blind[r]: shas[r] for r in ordered},
                "grades": {blind[r]: {s: previous.get(r, {}).get(s) for s in sections} for r in ordered},
                "notes": {blind[r]: "" for r in ordered},
            },
            sort_keys=False,
            allow_unicode=True,
        )
    )
    (out_dir / BLIND_KEY_FILE).write_text(
        "# Blind label -> real candidate. Do not open until every grade is filled.\n"
        + yaml.safe_dump({blind[r]: r for r in ordered}, sort_keys=False)
    )
    return review_path


def _load_review(out_dir: Path) -> dict:
    """review.yaml with blind labels translated back to real candidates."""
    review = yaml.safe_load((Path(out_dir) / REVIEW_FILE).read_text())
    key = yaml.safe_load((Path(out_dir) / BLIND_KEY_FILE).read_text())
    review["candidates"] = {key[k]: v for k, v in review["candidates"].items()}
    review["grades"] = {key[k]: v for k, v in review["grades"].items()}
    return review


def _norm(value):
    if value is None:
        return None
    text = str(value).strip()
    if text in {"0", "1", "2"}:
        return int(text)
    raise ValueError(f"grade must be 0, 1 or 2, got {value!r}")


def finalize(out_dir: Path, judge_dir: Path) -> dict:
    from .judge import DEFAULT_PRINCIPLES, graded_sections

    review = _load_review(out_dir)
    grades = _load_grades(judge_dir)
    sections = graded_sections(DEFAULT_PRINCIPLES.read_text())
    stray = sorted({s for row in review["grades"].values() for s in row} - set(sections))
    if stray:
        return {"error": "review.yaml names sections that are not graded", "problems": stray}
    problems = _binding_problems(review.get("principles_sha256"), review["candidates"], grades)
    if problems:
        return {"error": "artifact/edition binding mismatch", "problems": problems}

    cells = agree = 0
    unfilled = 0
    by_section: dict = {}
    misses: list = []
    for label, row in review["grades"].items():
        for section in sections:
            human = _norm(row.get(section))
            if human is None:
                unfilled += 1
                continue
            judge, _ = _cell(grades, label, section)
            cells += 1
            hit = judge == human
            agree += hit
            stats = by_section.setdefault(section, [0, 0])
            stats[0] += hit
            stats[1] += 1
            if not hit:
                misses.append({"module": label, "section": section, "human": human, "judge": judge})

    raw = round(agree / cells, 3) if cells else None
    result = {
        "fixture": review["fixture"],
        "judge_model": grades.get("judge_model"),
        "method": "exact per-cell agreement with the doctrine owner's section grades (0/1/2)",
        "cells": cells,
        "agreement": raw,
        "by_section": {s: round(a / n, 3) for s, (a, n) in by_section.items()},
        "misses": misses,
        "unfilled": unfilled,
    }
    if unfilled:
        result["error"] = f"refusing to stamp: {unfilled} unfilled cell(s)"
        return result

    enough = cells >= MIN_CELLS
    failing = sorted(s for s, v in result["by_section"].items() if v < GATE)
    result["failing_sections"] = failing
    status = (
        f"experimental (needs >= {MIN_CELLS} cells)" if not enough
        else f"experimental (sections below {GATE}: {', '.join(failing)})" if failing
        else "calibrated (every section agrees with the doctrine owner)"
    )
    grades["calibration"] = result
    grades["agreement"] = raw
    grades["agreement_method"] = result["method"]
    grades["status"] = status
    (Path(judge_dir) / "grades.json").write_text(json.dumps(grades, indent=2))
    result["status"] = status
    return result
