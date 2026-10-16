"""Markdown report from Inspect eval logs.

One row per (model, fixture): pass rate as k/n with a Wilson 95% interval,
median assistant turns, median output tokens, median diff lines, and terminal
state counts. Models are sorted alphabetically — no ranking at this stage.

Wilson, not normal approximation: at n=5..10 the normal interval is badly
wrong, and the interval is the point — 4/5 is not a measurement.
"""

from __future__ import annotations

import random
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
    seed: int | None = None
    invariants: dict | None = None
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
    rubric_sha: str | None = None
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
                    seed=meta.get("seed", (sample.metadata or {}).get("seed")),
                    invariants=meta.get("invariants"),
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
                    rubric_sha=meta.get("rubric_sha"),
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


def _failed_invariants(group: list) -> str:
    """Per-invariant failure attribution across a group's attempts."""
    counts: dict = {}
    for a in group:
        for name, ok in (a.invariants or {}).items():
            if not ok:
                counts[name] = counts.get(name, 0) + 1
    if not counts:
        return "—"
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
        f"| {_failed_invariants(group)} "
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


def _current_rubric_sha(fixture_id: str) -> str | None:
    """The scoring edition currently in the tree for this fixture — attempts
    scored under an older rubric must never pool into the same medians."""
    try:
        from .generation import GenerationFixture
        from .paths import find_fixture_dir

        return GenerationFixture.load(find_fixture_dir(fixture_id)).rubric_sha
    except Exception:
        return None


def _filter_current_edition(gen: list) -> tuple:
    """(attempts scored under the current rubric edition, stale count).
    Attempts without a recorded rubric_sha predate edition stamping and are
    treated as stale once a current edition is known."""
    current: list = []
    stale = 0
    shas: dict = {}
    for a in gen:
        if a.fixture not in shas:
            shas[a.fixture] = _current_rubric_sha(a.fixture)
        expected = shas[a.fixture]
        if expected is None or a.rubric_sha == expected:
            current.append(a)
        else:
            stale += 1
    return current, stale


def _load_grade_data(judge_dirs: list) -> list:
    """One entry per grades.json: {fixture, judge_model, detail, weights,
    calibrated, status, principles}. Grades from different judges or fixtures
    are never blended into one lookup table."""
    import json

    entries: list = []
    for d in judge_dirs or []:
        path = Path(d) / "grades.json"
        if not path.is_file():
            continue
        data = json.loads(path.read_text())
        if data.get("author_label"):
            # Bias-experiment grades: the judge was told an author. Never scored.
            continue
        entries.append({
            "fixture": data.get("fixture"),
            "judge_model": data.get("judge_model", "?"),
            "detail": data.get("detail") or {},
            "weights": data.get("section_weights") or {},
            "calibrated": str(data.get("status", "")).startswith("calibrated"),
            "status": str(data.get("status", "experimental")),
            "principles": data.get("principles_sha256") or "—",
        })
    return entries


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


def _matched_grades(model: str, fixture: str, group: list, grade_entries: list) -> tuple:
    """(calibrated sha-matched grades, notes). A grade joins only when its
    judge file is calibrated AND it was computed over one of this group's
    artifacts (module_sha match, when both sides carry hashes)."""
    grades: list = []
    notes: list = []
    attempt_shas = {a.module_sha for a in group if a.module_sha}
    for entry in grade_entries:
        if entry["fixture"] not in (None, fixture):
            continue
        hit = _grade_for_model(model, entry["detail"])
        if hit is None:
            continue
        graded_sha = hit.get("module_sha")
        if graded_sha and attempt_shas and graded_sha not in attempt_shas:
            notes.append(
                f"{model}: {entry['judge_model']} grade computed over a different module snapshot — excluded"
            )
            continue
        if not entry["calibrated"]:
            notes.append(
                f"{model}: {entry['judge_model']} grade is {entry['status']!r} — shown, not folded in"
            )
            grades.append((hit["overall"], False))
            continue
        grades.append((hit["overall"], True))
    return grades, notes


def render_leaderboard(attempts: list, judge_dirs: list) -> str:
    """Composite 0-100 grades per composite-scoring-policy.yaml, aggregated
    over EVERY attempt scored under the current rubric edition (median +
    range, never a single draw). Rows without a usable calibrated grade are
    NEVER ranked against graded rows — a mechanical-only composite sits on a
    different scale, and falling back to it would reward dodging the judge."""
    policy = _load_policy()
    gen = [a for a in attempts if a.kind == "generation"]
    if not policy or not gen:
        return ""
    gen, stale = _filter_current_edition(gen)
    grade_entries = _load_grade_data(judge_dirs)
    w = policy["weights"]
    groups: dict = {}
    for a in gen:
        if a.mechanical_score is not None and a.semantic_score is not None:
            groups.setdefault((a.model, a.fixture), []).append(a)

    notes: list = []
    if stale:
        notes.append(
            f"{stale} attempt(s) scored under an older rubric edition excluded from all aggregates"
        )
    graded_rows: list = []
    ungraded_rows: list = []
    for (model, fixture), group in groups.items():
        rubrics = [a.semantic_score for a in group]
        mechs = [a.mechanical_score for a in group]
        exps = [
            sum(a.expertise.values()) / len(a.expertise)
            for a in group if a.expertise
        ]
        grades, g_notes = _matched_grades(model, fixture, group, grade_entries)
        notes.extend(g_notes)
        calibrated_grades = [g for g, ok in grades if ok]
        shown_grades = [g for g, _ in grades]
        grade = statistics.median(calibrated_grades) if calibrated_grades else None
        grade_cell = (
            f"{grade:.0f}" if grade is not None
            else (f"{statistics.median(shown_grades):.0f} (experimental)" if shown_grades else "—")
        )

        findings: dict = {}
        for a in group:
            for item in a.mandatory_failures or []:
                findings[item] = findings.get(item, 0) + 1
        flag = (
            " ".join(f"⚠{item}({c}/{len(group)})" for item, c in sorted(findings.items()))
            if findings else "—"
        )
        base = {
            "model": model, "fixture": fixture, "n": len(group),
            "rubric": statistics.median(rubrics),
            "exp": statistics.median(exps) if exps else None,
            "mech": statistics.median(mechs),
            "grade_cell": grade_cell, "flag": flag, "findings": findings,
        }
        if grade is not None:
            composites = sorted(
                100 * (w["mechanical"] * m + w["grade"] * grade / 100) for m in mechs
            )
            base["composite"] = statistics.median(composites)
            base["range"] = (
                f"{composites[0]:.0f}–{composites[-1]:.0f}" if len(group) > 1 else "—"
            )
            graded_rows.append(base)
        else:
            mech_scaled = sorted(100 * m for m in mechs)
            base["composite"] = None
            base["mech_med"] = statistics.median(mech_scaled)
            base["range"] = (
                f"{mech_scaled[0]:.0f}–{mech_scaled[-1]:.0f}" if len(group) > 1 else "—"
            )
            ungraded_rows.append(base)

    lines = [
        "",
        f"## Composite grades (scoring policy {policy.get('policy_version', '?')} — "
        "0.70·mechanical + 0.30·calibrated judge grade)",
        "",
    ]
    header = (
        "| model | fixture | n | rubric (med) | expertise (med) | mechanical (med) "
        "| judge grade | **composite (med)** | range | findings |"
    )
    sep = "|-------|---------|---|--------------|-----------------|------------------|-------------|---------------------|-------|----------|"
    if graded_rows:
        lines += [header, sep]
        for r in sorted(graded_rows, key=lambda r: -r["composite"]):
            exp = f"{r['exp']:.2f}" if r["exp"] is not None else "—"
            lines.append(
                f"| {r['model']} | {r['fixture']} | {r['n']} | {r['rubric']:.3f} | {exp} "
                f"| {r['mech']:.3f} | {r['grade_cell']} | **{r['composite']:.0f}** "
                f"| {r['range']} | {r['flag']} |"
            )
    if ungraded_rows:
        lines += [
            "",
            "### Not ranked — no calibrated judge grade (mechanical scores only)",
            "",
            "| model | fixture | n | rubric (med) | expertise (med) | mechanical (med, ×100) | judge grade | range | findings |",
            "|-------|---------|---|--------------|-----------------|------------------------|-------------|-------|----------|",
        ]
        for r in sorted(ungraded_rows, key=lambda r: r["model"]):
            exp = f"{r['exp']:.2f}" if r["exp"] is not None else "—"
            lines.append(
                f"| {r['model']} | {r['fixture']} | {r['n']} | {r['rubric']:.3f} | {exp} "
                f"| {r['mech_med']:.0f} | {r['grade_cell']} | {r['range']} | {r['flag']} |"
            )
        lines.append("")
        lines.append(
            "Mechanical-only rows sit on a different scale than composites and are "
            "deliberately not ranked against graded rows."
        )
    lines.append("")
    lines.append(
        "Composites aggregate every current-edition attempt (median; range = min–max). "
        "Ranking claims are only supported where ranges do not overlap. Rows with n=1 "
        "are single draws, not measurements."
    )
    for note in sorted(set(notes)):
        lines.append(f"- {note}")

    findings_lines = []
    for r in sorted(graded_rows + ungraded_rows, key=lambda r: r["model"]):
        for item, c in sorted(r["findings"].items()):
            findings_lines.append(
                f"- **{r['model']}** ({r['fixture']}): failed mandatory item `{item}` in {c}/{r['n']} attempt(s)"
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
    """Judged grades broken out per doctrine section, one table per judge —
    readers who reject a specific preference can discount exactly that row,
    and cross-family judges are compared side by side, never blended."""
    from .judge import _spearman

    entries = _load_grade_data(judge_dirs)
    blocks: list = []
    for entry in entries:
        detail = entry["detail"]
        if not detail:
            continue
        labels = sorted(detail)
        sections: list = []
        for e in detail.values():
            for s in e.get("sections") or {}:
                if s not in sections:
                    sections.append(s)
        lines = [
            "",
            f"## Judged grades by doctrine section — {entry['judge_model']} "
            f"({entry['status']}; doctrine edition {entry['principles']})",
            "",
            "| doctrine section | " + " | ".join(labels) + " |",
            "|" + "---|" * (len(labels) + 1),
        ]
        weights = entry["weights"]
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
        pairs = [
            (detail[label]["overall"], detail[label]["tf_sloc"])
            for label in labels
            if detail[label].get("overall") is not None and detail[label].get("tf_sloc")
        ]
        if len(pairs) >= 4:
            rho = _spearman([p[0] for p in pairs], [p[1] for p in pairs])
            if rho is not None:
                lines.append("")
                lines.append(
                    f"Length-bias check: Spearman(grade, TF SLOC) = {rho:+.2f} over "
                    f"{len(pairs)} candidates — published so a verbosity-shaped judge "
                    "cannot hide."
                )
        unparsed = sorted({
            s for e in detail.values() for s in e.get("unparsed_sections") or []
        })
        if unparsed:
            lines.append("")
            lines.append(
                f"⚠ sections with parsing loss (overall withheld for affected candidates): {', '.join(unparsed)}"
            )
        blocks.append("\n".join(lines))
    if not blocks:
        return ""
    footer = (
        "\nEach row is scored 0–2 against one section of the published doctrine "
        "(median of independent samples). "
        "The sections are our documented preferences — disagree with one, ignore its "
        "row; the mechanical rubric above is judge-free."
    )
    return "\n".join(blocks) + footer


def render_generation_sections(attempts: list) -> str:
    """Generation fixture sections: rubric scores + expertise differential."""
    gen = [a for a in attempts if a.kind == "generation"]
    if not gen:
        return ""
    gen, _ = _filter_current_edition(gen)
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
        "verified, and pooled into the mechanical score at exactly weight 1 per item."
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


def render_paired_differences(attempts: list, min_shared: int = 5) -> str:
    """Fix-domain paired model comparisons: per-task pass-rate differences
    over the tasks (fixture, seed) both models attempted, with a paired
    bootstrap CI over tasks. The pairing removes shared task difficulty —
    far tighter than comparing two marginal pass rates — and a delta whose
    CI spans zero is printed as not resolvable, never as a ranking."""
    fix = [a for a in attempts if a.kind == "fix" and a.seed is not None]
    per_task: dict = {}
    for a in fix:
        per_task.setdefault(a.model, {}).setdefault((a.fixture, a.seed), []).append(a.passed)
    models = sorted(per_task)
    if len(models) < 2:
        return ""
    rng = random.Random(0)
    lines = [
        "",
        "## Paired model differences (fix domain)",
        "",
        "| pair | shared tasks | Δ pass (pp) | 95% CI (paired bootstrap) | resolvable? |",
        "|------|--------------|-------------|---------------------------|-------------|",
    ]
    emitted = False
    for i, a_model in enumerate(models):
        for b_model in models[i + 1:]:
            shared = sorted(set(per_task[a_model]) & set(per_task[b_model]))
            if len(shared) < min_shared:
                continue
            diffs = [
                statistics.mean(per_task[a_model][t]) - statistics.mean(per_task[b_model][t])
                for t in shared
            ]
            point = statistics.mean(diffs) * 100
            resamples = sorted(
                statistics.mean(rng.choices(diffs, k=len(diffs))) * 100
                for _ in range(2000)
            )
            lo, hi = resamples[49], resamples[1949]
            resolvable = "yes" if lo > 0 or hi < 0 else "no (n.s.)"
            lines.append(
                f"| {a_model} − {b_model} | {len(shared)} | {point:+.1f} "
                f"| [{lo:+.1f}, {hi:+.1f}] | {resolvable} |"
            )
            emitted = True
    if not emitted:
        return ""
    n = max(
        len(set(per_task[a]) & set(per_task[b]))
        for i, a in enumerate(models) for b in models[i + 1:]
    )
    mdd = 2.8 * (0.5 / n) ** 0.5 * 100
    lines.append("")
    lines.append(
        f"Minimum detectable difference at n={n} shared tasks: ~{mdd:.0f} pp "
        "(worst case p=0.5, 80% power, two-sided α=0.05, unpaired approximation — "
        "the paired design above is tighter). Deltas below this are not resolvable "
        "by this benchmark; adding tasks, not epochs, is what shrinks it."
    )
    return "\n".join(lines)


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
        "| model | fixture | duration | tokens in/out | est. cost | TF SLOC | comment ratio | variables | checkov |",
        "|-------|---------|----------|---------------|-----------|---------|---------------|-----------|---------|",
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
        checkov = s.get("checkov_failed")
        lines.append(
            f"| {model} | {fixture} | {duration} | {tokens} | {cost_str} "
            f"| {s.get('tf_sloc', '—')} | {s.get('comment_ratio', '—')} "
            f"| {s.get('variable_count', '—')} "
            f"| {checkov if checkov is not None else '—'} |"
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
            f"{prices.get('snapshot_date', '?')} (cache reads/writes included).{note} "
            "checkov = failed checks reported by checkov when installed; descriptive only."
        )
    return "\n".join(lines)


def render_report(attempts: list) -> str:
    fix_attempts = [a for a in attempts if a.kind == "fix"]
    lines = [
        "# iacbench report",
        "",
        "## Fix fixtures",
        "",
        "| model | fixture | pass | Wilson 95% | med turns | med out tokens | med diff lines | failed invariants | terminal states |",
        "|-------|---------|------|------------|-----------|----------------|----------------|-------------------|-----------------|",
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
        "## Judged rankings (blind pairwise, Bradley-Terry — discovery/audit, never scored)",
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
    paired = render_paired_differences(attempts)
    if paired:
        text += paired + "\n"
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
