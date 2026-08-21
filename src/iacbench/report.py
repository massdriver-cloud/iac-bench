"""Markdown report from Inspect eval logs.

One row per (model, fixture): pass rate as k/n with a Wilson 95% interval,
median assistant turns, median output tokens, median diff lines, and terminal
state counts. One roll-up row per model. Models are sorted alphabetically —
no ranking at this stage.

Wilson, not normal approximation: at n=5..10 the normal interval is badly
wrong, and the interval is the point — 4/5 is not a measurement.
"""

from __future__ import annotations

import statistics
from dataclasses import dataclass
from pathlib import Path

from inspect_ai.log import read_eval_log

from . import SCAFFOLD_CONTRACT_VERSION, SUITE_VERSION


def wilson_interval(k: int, n: int, z: float = 1.96) -> tuple:
    """Wilson score interval for k successes in n trials."""
    if n == 0:
        return (0.0, 1.0)
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / denom
    return (max(0.0, center - half), min(1.0, center + half))


@dataclass
class Attempt:
    model: str
    fixture: str
    passed: bool
    terminal_state: str
    turns: int | None = None
    output_tokens: int | None = None
    diff_lines: int | None = None
    tofu_version: str | None = None
    created: str | None = None
    # descriptive-statistics fields (informational, never scored)
    input_tokens: int | None = None
    cache_read_tokens: int | None = None
    cache_write_tokens: int | None = None
    duration_s: float | None = None
    stats: dict | None = None
    expertise: dict | None = None
    expertise_score: float | None = None
    semantic_score: float | None = None
    mechanical_score: float | None = None
    mandatory_failures: list | None = None
    module_sha: str | None = None
    kind: str = "fix"  # "fix" (binary invariants) or "generation" (fractional rubric)


def _terminal_state(sample) -> str:
    if sample.error is not None:
        return "harness_error"
    limit = getattr(sample, "limit", None)
    if limit is not None:
        limit_type = getattr(limit, "type", str(limit))
        if "message" in str(limit_type):
            return "turn_limit_exceeded"
        if "time" in str(limit_type):
            return "wall_clock_exceeded"
        return f"limit_{limit_type}"
    return "completed"


def collect_attempts(log_dir: Path) -> list:
    attempts: list = []
    for log_path in sorted(Path(log_dir).glob("*.eval")):
        log = read_eval_log(str(log_path))
        model = str(log.eval.model)
        if model.startswith("mockllm/"):
            continue
        created = getattr(log.eval, "created", None)
        for sample in log.samples or []:
            scores = sample.scores or {}
            scorer_name = next(iter(scores.keys()), "")
            score = next(iter(scores.values()), None)
            kind = "generation" if "generation" in scorer_name else "fix"
            meta = (score.metadata if score else None) or {}
            fixture = meta.get("fixture") or (sample.metadata or {}).get("fixture", "?")
            usage = sample.model_usage or {}
            output_tokens = sum(u.output_tokens or 0 for u in usage.values()) or None
            duration = getattr(sample, "working_time", None) or getattr(sample, "total_time", None)
            attempts.append(
                Attempt(
                    model=model,
                    fixture=str(fixture),
                    passed=bool(
                        score
                        and (score.value == 1.0 or getattr(score, "answer", None) == "pass")
                    ),
                    terminal_state=_terminal_state(sample),
                    turns=sum(1 for m in (sample.messages or []) if m.role == "assistant") or None,
                    output_tokens=output_tokens,
                    diff_lines=(
                        meta["efficiency"]["diff_lines_added"] + meta["efficiency"]["diff_lines_removed"]
                        if "efficiency" in meta
                        else None
                    ),
                    tofu_version=meta.get("tofu_version"),
                    created=str(created) if created else None,
                    input_tokens=sum(u.input_tokens or 0 for u in usage.values()) or None,
                    cache_read_tokens=sum(getattr(u, "input_tokens_cache_read", None) or 0 for u in usage.values()) or None,
                    cache_write_tokens=sum(getattr(u, "input_tokens_cache_write", None) or 0 for u in usage.values()) or None,
                    duration_s=float(duration) if duration else None,
                    stats=meta.get("stats"),
                    expertise=meta.get("expertise"),
                    expertise_score=meta.get("expertise_score"),
                    semantic_score=meta.get("semantic_score", score.value if score else None),
                    mechanical_score=meta.get("mechanical_score"),
                    mandatory_failures=meta.get("mandatory_failures"),
                    module_sha=meta.get("module_sha"),
                    kind=kind,
                )
            )
    return attempts


def _load_prices() -> dict | None:
    import yaml

    from .paths import REPO_ROOT

    prices_path = REPO_ROOT / "prices.yaml"
    if not prices_path.is_file():
        return None
    return yaml.safe_load(prices_path.read_text())


def estimate_cost(a: Attempt, prices: dict) -> float | None:
    """Estimated USD cost from the prices.yaml snapshot. Informational only."""
    model_prices = None
    for key, p in (prices.get("models") or {}).items():
        if key in a.model:
            model_prices = p
            break
    if model_prices is None or a.input_tokens is None:
        return None
    p_in = model_prices["input"] / 1_000_000
    p_out = model_prices["output"] / 1_000_000
    cost = (a.input_tokens or 0) * p_in + (a.output_tokens or 0) * p_out
    cost += (a.cache_read_tokens or 0) * p_in * prices.get("cache_read_multiplier", 0.1)
    cost += (a.cache_write_tokens or 0) * p_in * prices.get("cache_write_multiplier", 1.25)
    return cost


def _median(values: list) -> str:
    vals = [v for v in values if v is not None]
    return str(round(statistics.median(vals), 1)) if vals else "—"


def _states(group: list) -> str:
    counts: dict = {}
    for a in group:
        counts[a.terminal_state] = counts.get(a.terminal_state, 0) + 1
    if set(counts) == {"completed"}:
        return "all completed"
    return ", ".join(f"{k}:{v}" for k, v in sorted(counts.items()))


def _row(label: tuple, group: list) -> str:
    n = len(group)
    k = sum(1 for a in group if a.passed)
    lo, hi = wilson_interval(k, n)
    return (
        f"| {label[0]} | {label[1]} | {k}/{n} | [{lo:.2f}, {hi:.2f}] "
        f"| {_median([a.turns for a in group])} "
        f"| {_median([a.output_tokens for a in group])} "
        f"| {_median([a.diff_lines for a in group])} "
        f"| {_states(group)} |"
    )


def _latest_per_model(attempts: list) -> dict:
    """(model, fixture) -> latest attempt, by log creation time."""
    latest: dict = {}
    for a in attempts:
        key = (a.model, a.fixture)
        if key not in latest or (a.created or "") >= (latest[key].created or ""):
            latest[key] = a
    return latest


def _load_policy() -> dict | None:
    import yaml

    from .paths import REPO_ROOT

    path = REPO_ROOT / "composite-scoring-policy.yaml"
    return yaml.safe_load(path.read_text()) if path.is_file() else None


def _load_grade_data(judge_dirs: list) -> dict:
    """Merged absolute-grade data from grades.json files.

    Returns {detail: {label: {overall, sections, module_sha}}, calibrated: bool,
    status: str, principles: str}. Grades count as calibrated only when EVERY
    loaded file says so — the report never folds an uncalibrated grade into
    the composite, matching the benchmark's stated gate."""
    import json

    detail: dict = {}
    statuses: list = []
    principles: set = set()
    weights: dict = {}
    for d in judge_dirs or []:
        path = Path(d) / "grades.json"
        if not path.is_file():
            continue
        data = json.loads(path.read_text())
        detail.update(data.get("detail") or {})
        weights.update(data.get("section_weights") or {})
        statuses.append(str(data.get("status", "experimental")))
        if data.get("principles_sha256"):
            principles.add(data["principles_sha256"])
    return {
        "detail": detail,
        "weights": weights,
        "calibrated": bool(statuses) and all(s.startswith("calibrated") for s in statuses),
        "status": "; ".join(sorted(set(statuses))) or "no grades",
        "principles": ", ".join(sorted(principles)) or "—",
    }


def _grade_for_model(model: str, detail: dict) -> dict | None:
    """Exact-normalized label match: the candidate label must equal the model
    id, its provider-stripped tail, or the tail minus a 'claude-' prefix.
    Substring matching is banned — a label like '5' must never match a row."""
    tail = model.split("/")[-1]
    acceptable = {model, tail, tail.removeprefix("claude-")}
    for label, entry in detail.items():
        if label in acceptable and entry.get("overall") is not None:
            return entry
    return None


def render_leaderboard(attempts: list, judge_dirs: list) -> str:
    """Composite 0-100 grades per composite-scoring-policy.yaml, aggregated
    over EVERY attempt (median + range, never a single draw). Scores are TRUE
    values — mandatory (security) failures are flagged, listed as findings,
    and fail the verdict, but never cap or distort the numbers. The judge
    grade joins the composite only when its stored status is calibrated AND
    it was computed over the same artifact (module_sha match)."""
    policy = _load_policy()
    gen = [a for a in attempts if a.kind == "generation"]
    if not policy or not gen:
        return ""
    grade_data = _load_grade_data(judge_dirs)
    w = policy["weights"]
    groups: dict = {}
    for a in gen:
        if a.semantic_score is not None and a.mechanical_score is not None and a.expertise:
            groups.setdefault((a.model, a.fixture), []).append(a)

    notes: list = []
    rows = []
    for (model, fixture), group in groups.items():
        rubrics = [a.semantic_score for a in group]
        mechs = [a.mechanical_score for a in group]
        exps = [sum(a.expertise.values()) / len(a.expertise) for a in group]
        entry = _grade_for_model(model, grade_data["detail"])
        grade = entry.get("overall") if entry else None
        grade_cell = "—"
        use_grade = grade is not None and grade_data["calibrated"]
        if grade is not None:
            attempt_shas = {a.module_sha for a in group if a.module_sha}
            graded_sha = entry.get("module_sha")
            if graded_sha and attempt_shas and graded_sha not in attempt_shas:
                use_grade = False
                grade_cell = f"{grade:.0f} (stale artifact)"
                notes.append(
                    f"{model}: judge grade computed over a different module snapshot — excluded"
                )
            else:
                grade_cell = f"{grade:.0f}" if use_grade else f"{grade:.0f} (experimental)"
        if not use_grade and grade is not None and not grade_data["calibrated"]:
            notes.append(
                f"judge grades excluded from composite: status is {grade_data['status']!r}"
            )

        def composite(mech: float, grade=grade, use_grade=use_grade) -> float:
            if use_grade:
                return 100 * (w["mechanical"] * mech + w["grade"] * grade / 100)
            return 100 * mech  # mechanical-only: the composite IS the pooled score

        composites = sorted(composite(m) for m in mechs)
        findings: dict = {}
        for a in group:
            for item in a.mandatory_failures or []:
                findings[item] = findings.get(item, 0) + 1
        flag = (
            " ".join(f"⚠{item}({c}/{len(group)})" for item, c in sorted(findings.items()))
            if findings else "—"
        )
        rows.append((
            statistics.median(composites), model, fixture, len(group),
            statistics.median(rubrics), statistics.median(exps),
            statistics.median(mechs), grade_cell,
            f"{composites[0]:.0f}–{composites[-1]:.0f}" if len(group) > 1 else "—",
            flag, findings,
        ))

    mode = (
        "0.70·mechanical + 0.30·calibrated judge grade"
        if grade_data["calibrated"] and grade_data["detail"]
        else "mechanical only (pooled rubric + expertise); judge grade shown but not folded in"
    )
    lines = [
        "",
        f"## Composite grades (scoring policy {policy.get('policy_version', '?')} — {mode})",
        "",
        "| model | fixture | n | rubric (med) | expertise (med) | mechanical (med) | judge grade | **composite (med)** | range | findings |",
        "|-------|---------|---|--------------|-----------------|------------------|-------------|---------------------|-------|----------|",
    ]
    for med, model, fixture, n, rubric, exp, mech, grade_cell, rng, flag, _ in sorted(rows, reverse=True):
        lines.append(
            f"| {model} | {fixture} | {n} | {rubric:.3f} | {exp:.2f} | {mech:.3f} | {grade_cell} "
            f"| **{med:.0f}** | {rng} | {flag} |"
        )
    lines.append("")
    lines.append(
        "Composites aggregate every attempt (median; range = min–max). Ranking claims "
        "are only supported where ranges do not overlap. Rows with n=1 are single "
        "draws, not measurements."
    )
    for note in sorted(set(notes)):
        lines.append(f"- {note}")

    findings_lines = []
    for _, model, fixture, n, *_rest, findings in sorted(rows):
        for item, c in sorted(findings.items()):
            findings_lines.append(
                f"- **{model}** ({fixture}): failed mandatory item `{item}` in {c}/{n} attempt(s)"
            )
    if findings_lines:
        lines += ["", "### Security findings", ""]
        lines += findings_lines
        lines.append("")
        lines.append(
            "Findings fail the verdict but do not cap scores — the composite above is "
            "the true measured value; treat any ⚠ row as unshippable regardless of grade."
        )
    return "\n".join(lines)


def render_grade_sections(judge_dirs: list) -> str:
    """Judged grades broken out per doctrine section (docs/good-opentofu.md),
    one column per candidate — readers who reject a specific preference can
    discount exactly that row and keep the rest."""
    grade_data = _load_grade_data(judge_dirs)
    detail = grade_data["detail"]
    if not detail:
        return ""
    labels = sorted(detail)
    sections: list = []
    for entry in detail.values():
        for s in entry.get("sections") or {}:
            if s not in sections:
                sections.append(s)
    lines = [
        "",
        f"## Judged grades by doctrine section ({grade_data['status']}; "
        f"doctrine edition {grade_data['principles']})",
        "",
        "| doctrine section | " + " | ".join(labels) + " |",
        "|" + "---|" * (len(labels) + 1),
    ]
    weights = grade_data.get("weights") or {}
    for section in sections:
        cells = []
        for label in labels:
            v = (detail[label].get("sections") or {}).get(section)
            cells.append("—" if v is None else f"{v:g}")
        w = weights.get(section, 1)
        name = section if w == 1 else f"{section} (w{w:g})"
        lines.append(f"| {name} | " + " | ".join(cells) + " |")
    overall = [
        f"**{detail[label]['overall']:.0f}**" if detail[label].get("overall") is not None else "—"
        for label in labels
    ]
    lines.append("| **overall (0–100)** | " + " | ".join(overall) + " |")
    lines.append("")
    lines.append(
        "Each row is scored 0–4 against one section of the published doctrine "
        "(median of independent samples). The sections are our documented "
        "preferences — disagree with one, ignore its row; the mechanical rubric "
        "above is judge-free."
    )
    return "\n".join(lines)


def render_generation_sections(attempts: list) -> str:
    """Generation fixture sections: rubric scores + expertise differential."""
    gen = [a for a in attempts if a.kind == "generation"]
    if not gen:
        return ""
    lines = ["", "## Generation fixtures (rubric-scored)"]
    groups: dict = {}
    for a in gen:
        groups.setdefault((a.model, a.fixture), []).append(a)

    lines += [
        "",
        "| model | fixture | n | semantic score (med) | expertise | pass |",
        "|-------|---------|---|----------------------|-----------|------|",
    ]
    for (model, fixture), group in sorted(groups.items()):
        scores = [a.semantic_score for a in group if a.semantic_score is not None]
        med = f"{statistics.median(scores):.3f}" if scores else "—"
        with_exp = [a for a in group if a.expertise]
        exp = (
            f"{statistics.median(sum(a.expertise.values()) for a in with_exp):g}"
            f"/{len(with_exp[0].expertise)}"
            if with_exp else "—"
        )
        passed = sum(1 for a in group if a.passed)
        lines.append(
            f"| {model} | {fixture} | {len(group)} | {med} | {exp} | {passed}/{len(group)} |"
        )

    # expertise differential: one table per fixture, rows = items, cols = models;
    # cells show how many attempts exhibited the touch
    by_fixture: dict = {}
    for (model, fixture), group in groups.items():
        per_attempt = [a.expertise for a in group if a.expertise]
        if per_attempt:
            by_fixture.setdefault(fixture, {})[model] = per_attempt
    for fixture, per_model in sorted(by_fixture.items()):
        models = sorted(per_model)
        all_items = sorted({item for runs in per_model.values() for exp in runs for item in exp})
        labels = _expertise_labels(fixture)
        lines += ["", f"### Expertise differential — {fixture}", ""]
        lines.append("| expertise item | " + " | ".join(models) + " |")
        lines.append("|" + "---|" * (len(models) + 1))
        for item in all_items:
            cells = []
            for m in models:
                runs = per_model[m]
                hits = sum(1 for exp in runs if exp.get(item))
                if len(runs) == 1:
                    cells.append("✓" if hits else "—")
                else:
                    cells.append(f"{hits}/{len(runs)}")
            lines.append(f"| {labels.get(item, item)} | " + " | ".join(cells) + " |")
    lines.append("")
    lines.append(
        "Expertise items are discovered (mostly from judge rationales), mechanically "
        "verified, and never folded into the semantic score."
    )
    return "\n".join(lines)


def _expertise_labels(fixture_id: str) -> dict:
    try:
        from .generation import GenerationFixture
        from .paths import find_fixture_dir

        fixture = GenerationFixture.load(find_fixture_dir(fixture_id))
        return {e["id"]: f"{e['id']}: {e['description'].strip()}" for e in fixture.expertise}
    except Exception:
        return {}


def render_stats_section(attempts: list) -> str:
    """Descriptive statistics: duration, tokens, estimated cost, SLOC. Never scored."""
    latest = _latest_per_model(attempts)
    if not latest:
        return ""
    prices = _load_prices()
    lines = [
        "",
        "## Run statistics (informational — never scored)",
        "",
        "| model | fixture | duration | tokens in/out | est. cost | TF SLOC | comment ratio | variables |",
        "|-------|---------|----------|---------------|-----------|---------|---------------|-----------|",
    ]
    for (model, fixture), a in sorted(latest.items()):
        duration = f"{a.duration_s:.0f}s" if a.duration_s else "—"
        # Cache reads carry most of the prompt volume for cache-heavy
        # providers — raw in/out alone badly misstates traffic.
        cache = (
            f" (+{a.cache_read_tokens:,}cr/{a.cache_write_tokens or 0:,}cw)"
            if a.cache_read_tokens else ""
        )
        tokens = (
            f"{a.input_tokens:,}/{a.output_tokens:,}{cache}"
            if a.input_tokens and a.output_tokens else "—"
        )
        cost = estimate_cost(a, prices) if prices else None
        cost_str = f"${cost:.3f}" if cost is not None else "—"
        s = a.stats or {}
        lines.append(
            f"| {model} | {fixture} | {duration} | {tokens} | {cost_str} "
            f"| {s.get('tf_sloc', '—')} | {s.get('comment_ratio', '—')} "
            f"| {s.get('variable_count', '—')} |"
        )
    if prices:
        note = ""
        for p in (prices.get("models") or {}).values():
            if p.get("note"):
                note = f" Note: {p['note']}."
                break
        lines.append("")
        lines.append(
            f"Costs are estimates from the prices.yaml snapshot dated "
            f"{prices.get('snapshot_date', '?')} (cache reads/writes included).{note}"
        )
    return "\n".join(lines)


def render_report(attempts: list) -> str:
    fix_attempts = [a for a in attempts if a.kind == "fix"]
    lines = [
        "# iacbench report",
        "",
        "## Fix fixtures",
        "",
        "| model | fixture | pass | Wilson 95% | med turns | med out tokens | med diff lines | terminal states |",
        "|-------|---------|------|------------|-----------|----------------|----------------|-----------------|",
    ]
    groups: dict = {}
    for a in fix_attempts:
        groups.setdefault((a.model, a.fixture), []).append(a)
    for key in sorted(groups):
        lines.append(_row(key, groups[key]))
    if groups and all(all(a.passed for a in g) for g in groups.values()):
        lines += [
            "",
            "All fix fixtures are saturated (every model passes every attempt): they "
            "verify the harness and anti-cheat invariants but do not discriminate "
            "between models. Do not rank on this table.",
        ]

    tofu_versions = sorted({a.tofu_version for a in attempts if a.tofu_version})
    dates = sorted(a.created for a in attempts if a.created)
    lines += [
        "",
        "---",
        f"suite_version: {SUITE_VERSION} · scaffold_contract_version: {SCAFFOLD_CONTRACT_VERSION} · "
        f"tofu: {', '.join(tofu_versions) or 'unknown'} · "
        f"runs: {dates[0][:10]} → {dates[-1][:10]}" if dates else "runs: none",
        "",
        f"Attempts: {len(attempts)}. Intervals are Wilson 95%; at small n they are wide on purpose — "
        "a 4/5 is not a measurement.",
    ]
    return "\n".join(lines) + "\n"


def render_judge_section(judge_dirs: list) -> str:
    """Pairwise-ranking section from judge scores.json files. The calibration
    label comes from the persisted agreement — never assumed."""
    import json

    lines = [
        "",
        "## Judged rankings (blind pairwise, Bradley-Terry)",
        "",
        "| fixture | judge model | principles | judgments | calibration | ranking |",
        "|---------|-------------|------------|-----------|-------------|---------|",
    ]
    found = False
    for d in judge_dirs:
        scores_path = Path(d) / "scores.json"
        if not scores_path.is_file():
            lines.append(f"| — | — | — | — | — | no scores.json in {d} |")
            continue
        s = json.loads(scores_path.read_text())
        found = True
        ranking = " › ".join(f"{label} {v}" for label, v in s.get("bt_scores", {}).items())
        if s.get("agreement") is not None:
            calibration = f"{s.get('status', '?')} ({s['agreement']:.2f} vs human, {s.get('graded_pairs', '?')} pairs)"
        else:
            calibration = s.get("status", "experimental")
        lines.append(
            f"| {s.get('fixture', '?')} | {s.get('judge_model', '?')} "
            f"| {s.get('principles_sha256') or '—'} | {s.get('judgments', '?')} "
            f"| {calibration} | {ranking} |"
        )
    lines.append("")
    lines.append(
        "Judged scores are a separate instrument from the mechanical invariants above "
        "and are never folded into them."
    )
    return "\n".join(lines) if found or judge_dirs else ""


def run_report(log_dir: Path, out: Path | None, judge_dirs: list | None = None) -> int:
    attempts = collect_attempts(log_dir)
    if not attempts:
        print(f"no scored attempts found in {log_dir}")
        return 1
    text = render_report(attempts)
    leaderboard = render_leaderboard(attempts, judge_dirs or [])
    if leaderboard:
        text += leaderboard + "\n"
    gen_section = render_generation_sections(attempts)
    if gen_section:
        text += gen_section + "\n"
    grade_sections = render_grade_sections(judge_dirs or [])
    if grade_sections:
        text += grade_sections + "\n"
    stats_section = render_stats_section(attempts)
    if stats_section:
        text += stats_section + "\n"
    if judge_dirs:
        text += render_judge_section(judge_dirs) + "\n"
    if out:
        Path(out).write_text(text)
        print(f"wrote {out} ({len(attempts)} attempts)")
    else:
        print(text)
    return 0
