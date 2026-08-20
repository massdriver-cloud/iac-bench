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
    mandatory_failures: list | None = None
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
                    mandatory_failures=meta.get("mandatory_failures"),
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

    path = REPO_ROOT / "scoring-policy.yaml"
    return yaml.safe_load(path.read_text()) if path.is_file() else None


def _load_grades(judge_dirs: list) -> dict:
    """candidate-label -> absolute grade, from grades.json in judge dirs."""
    import json

    grades: dict = {}
    for d in judge_dirs or []:
        path = Path(d) / "grades.json"
        if path.is_file():
            grades.update(json.loads(path.read_text()).get("grades", {}))
    return grades


def _grade_for_model(model: str, grades: dict) -> float | None:
    for label, grade in grades.items():
        if label in model and grade is not None:
            return grade
    return None


def render_leaderboard(attempts: list, judge_dirs: list) -> str:
    """Composite 0-100 grades per scoring-policy.yaml. Scores are TRUE values —
    mandatory (security) failures are flagged, listed as findings, and fail the
    verdict, but never cap or distort the numbers."""
    policy = _load_policy()
    gen = [a for a in attempts if a.kind == "generation"]
    if not policy or not gen:
        return ""
    grades = _load_grades(judge_dirs)
    w = policy["weights"]
    latest = _latest_per_model(gen)

    lines = [
        "",
        f"## Composite grades (scoring policy {policy.get('policy_version', '?')})",
        "",
        "| model | fixture | rubric | expertise | judge grade | **composite** | findings |",
        "|-------|---------|--------|-----------|-------------|---------------|----------|",
    ]
    rows = []
    for (model, fixture), a in latest.items():
        rubric = a.semantic_score
        exp_frac = (
            sum(a.expertise.values()) / len(a.expertise) if a.expertise else None
        )
        grade = _grade_for_model(model, grades)
        if rubric is None or exp_frac is None or grade is None:
            continue
        composite = 100 * (
            w["rubric"] * rubric + w["expertise"] * exp_frac + w["grade"] * grade / 100
        )
        flag = f"⚠ {len(a.mandatory_failures)}" if a.mandatory_failures else "—"
        rows.append((composite, model, fixture, rubric, exp_frac, grade, flag))
    for composite, model, fixture, rubric, exp_frac, grade, flag in sorted(rows, reverse=True):
        lines.append(
            f"| {model} | {fixture} | {rubric:.3f} | {exp_frac:.2f} | {grade:.1f} "
            f"| **{composite:.0f}** | {flag} |"
        )

    # security findings: every failed mandatory item, spelled out
    findings_lines = []
    for (model, fixture), a in sorted(latest.items()):
        for item in a.mandatory_failures or []:
            findings_lines.append(f"- **{model}** ({fixture}): failed mandatory item `{item}`")
    if findings_lines:
        lines += ["", "### Security findings", ""]
        lines += findings_lines
        lines.append("")
        lines.append(
            "Findings fail the verdict but do not cap scores — the composite above is "
            "the true measured value; treat any ⚠ row as unshippable regardless of grade."
        )
    return "\n".join(lines)


def render_generation_sections(attempts: list) -> str:
    """Generation fixture sections: rubric scores + expertise differential."""
    gen = [a for a in attempts if a.kind == "generation"]
    if not gen:
        return ""
    lines = ["", "## Generation fixtures (rubric-scored)"]
    latest = _latest_per_model(gen)

    lines += [
        "",
        "| model | fixture | semantic score | expertise | pass |",
        "|-------|---------|----------------|-----------|------|",
    ]
    for (model, fixture), a in sorted(latest.items()):
        exp = (
            f"{sum(a.expertise.values())}/{len(a.expertise)}"
            if a.expertise else "—"
        )
        lines.append(
            f"| {model} | {fixture} | {a.semantic_score if a.semantic_score is not None else '—'} "
            f"| {exp} | {'✓' if a.passed else '✗'} |"
        )

    # expertise differential: one table per fixture, rows = items, cols = models
    by_fixture: dict = {}
    for (model, fixture), a in latest.items():
        if a.expertise:
            by_fixture.setdefault(fixture, {})[model] = a.expertise
    for fixture, per_model in sorted(by_fixture.items()):
        models = sorted(per_model)
        all_items = sorted({item for exp in per_model.values() for item in exp})
        labels = _expertise_labels(fixture)
        lines += ["", f"### Expertise differential — {fixture}", ""]
        lines.append("| expertise item | " + " | ".join(models) + " |")
        lines.append("|" + "---|" * (len(models) + 1))
        for item in all_items:
            cells = " | ".join(
                "✓" if per_model[m].get(item) else "—" for m in models
            )
            lines.append(f"| {labels.get(item, item)} | {cells} |")
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
        tokens = (
            f"{a.input_tokens:,}/{a.output_tokens:,}"
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
        "| model | fixture | pass | Wilson 95% | med turns | med out tokens | med diff lines | terminal states |",
        "|-------|---------|------|------------|-----------|----------------|----------------|-----------------|",
    ]
    groups: dict = {}
    for a in fix_attempts:
        groups.setdefault((a.model, a.fixture), []).append(a)
    for key in sorted(groups):
        lines.append(_row(key, groups[key]))

    lines += ["", "## Roll-up per model", "",
              "| model | fixture | pass | Wilson 95% | med turns | med out tokens | med diff lines | terminal states |",
              "|-------|---------|------|------------|-----------|----------------|----------------|-----------------|"]
    by_model: dict = {}
    for a in fix_attempts:
        by_model.setdefault(a.model, []).append(a)
    for model in sorted(by_model):
        lines.append(_row((model, "(all)"), by_model[model]))

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
