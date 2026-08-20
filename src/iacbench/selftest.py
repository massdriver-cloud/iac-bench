"""Selftest: validate the checkers against known-answer solutions (spec §9).

For each fixture this verifies:
  1. rendering is deterministic for a given seed, and different seeds differ
  2. the fixture is genuinely broken at multiple seeds, with the declared error
  3. every solution directory under testdata/solutions/<id>/ scores as expected,
     including that the expected invariant is the one that failed

A subtly wrong invariant produces confident garbage downstream, so this exists
before (and independently of) the agent loop.
"""

from __future__ import annotations

import os
import re
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

from .checkers import (
    APPLY_INVARIANT_KEYS,
    INVARIANT_KEYS,
    score_directory,
    score_directory_apply,
    snapshot,
)
from .manifest import FixtureManifest
from .paths import PROVIDER_CACHE, SOLUTIONS_DIR, all_fixture_ids, find_fixture_dir
from .render import render_fixture
from .tofu import Tofu

_OVERLAY_SKIP = {".gitkeep", "expectations.yaml"}
_BROKEN_SEEDS = (0, 1)


@dataclass
class Failure:
    fixture: str
    check: str
    message: str


def _overlay(solution_dir: Path, work_dir: Path) -> None:
    for src in sorted(solution_dir.rglob("*")):
        if src.is_dir() or src.name in _OVERLAY_SKIP:
            continue
        rel = src.relative_to(solution_dir)
        dest = work_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dest)


def _broken_check(manifest: FixtureManifest, work_dir: Path, seed: int) -> list:
    failures = []
    pattern = re.compile(manifest.error_pattern)
    tofu = Tofu(work_dir, cache_dir=PROVIDER_CACHE)
    init_res = tofu.init()
    if init_res.exit_code != 0:
        # init validates config before installing providers, so a fixture can
        # be broken at init time — as long as it is the declared error
        combined = init_res.stderr + init_res.stdout
        if pattern.search(combined):
            return []
        return [
            Failure(
                manifest.id,
                f"broken@seed{seed}",
                f"tofu init failed with an error not matching {manifest.error_pattern!r}: "
                f"{combined.strip()[-500:]}",
            )
        ]
    res = tofu.validate()
    combined = res.stderr + res.stdout
    if res.exit_code == 0:
        res = tofu.plan()
        combined = res.stderr + res.stdout
    if res.exit_code == 0:
        failures.append(Failure(manifest.id, f"broken@seed{seed}", "fixture is not broken: validate and plan both succeed"))
    elif not pattern.search(combined):
        failures.append(
            Failure(
                manifest.id,
                f"broken@seed{seed}",
                f"error does not match pattern {manifest.error_pattern!r}; got: {combined.strip()[-500:]}",
            )
        )
    return failures


def _determinism_check(manifest: FixtureManifest, work_root: Path) -> list:
    failures = []
    render_a = work_root / "det-a"
    render_b = work_root / "det-b"
    render_c = work_root / "det-c"
    render_fixture(manifest, 42, render_a)
    render_fixture(manifest, 42, render_b)
    render_fixture(manifest, 0, render_c)
    if snapshot(render_a) != snapshot(render_b):
        failures.append(Failure(manifest.id, "determinism", "seed 42 rendered twice produced different bytes"))
    if snapshot(render_a) == snapshot(render_c):
        failures.append(Failure(manifest.id, "determinism", "seed 42 and seed 0 rendered identical output"))
    return failures


def _assert_expected(manifest: FixtureManifest, name: str, expect: dict, result) -> list:
    keys = APPLY_INVARIANT_KEYS if manifest.tier == 2 else INVARIANT_KEYS
    failures = []
    if result.verdict != expect["verdict"]:
        failures.append(
            Failure(
                manifest.id,
                name,
                f"expected verdict {expect['verdict']!r}, got {result.verdict!r} "
                f"(invariants: {result.invariants}; detail: {result.failure_detail})",
            )
        )
        return failures
    must_fail = expect.get("must_fail_any") or []
    if must_fail and not any(not result.invariants[keys[k]] for k in must_fail):
        failures.append(
            Failure(
                manifest.id,
                name,
                f"expected one of {must_fail} to fail, but invariants were: {result.invariants}",
            )
        )
    return failures


def _selftest_tier2(manifest: FixtureManifest, work_root: Path) -> list:
    """Tier-2 selftest: creates and destroys real cloud resources."""
    failures: list = []
    fixture_id = manifest.id
    pattern = re.compile(manifest.error_pattern)
    failures.extend(_determinism_check(manifest, work_root))

    def _cleanup(tofu: Tofu, label: str) -> None:
        destroy_res = tofu.destroy()
        if destroy_res.exit_code != 0:
            failures.append(
                Failure(fixture_id, label, f"CLEANUP FAILED — destroy exit {destroy_res.exit_code}; "
                        f"resources may be leaked (sweep with `iacbench sweep`): {destroy_res.stderr.strip()[-300:]}")
            )

    # brokenness at seed 0: initial apply must fail with the declared error
    broken_dir = work_root / "broken-seed0"
    render_fixture(manifest, 0, broken_dir)
    tofu = Tofu(broken_dir, cache_dir=PROVIDER_CACHE, timeout_s=300)
    init_res = tofu.init()
    if init_res.exit_code != 0:
        failures.append(Failure(fixture_id, "broken@seed0", f"tofu init failed: {init_res.stderr.strip()[-500:]}"))
        return failures
    apply_res = tofu.apply()
    combined = apply_res.stderr + apply_res.stdout
    if apply_res.exit_code == 0:
        failures.append(Failure(fixture_id, "broken@seed0", "fixture is not broken: initial apply succeeded"))
    elif not pattern.search(combined):
        failures.append(
            Failure(fixture_id, "broken@seed0",
                    f"apply error does not match pattern {manifest.error_pattern!r}: {combined.strip()[-500:]}")
        )
    _cleanup(tofu, "broken@seed0")

    # solution matrix at seed 0; each trial is a fresh render + initial apply
    expectations_path = SOLUTIONS_DIR / fixture_id / "expectations.yaml"
    if not expectations_path.is_file():
        failures.append(Failure(fixture_id, "solutions", f"missing {expectations_path}"))
        return failures
    expectations = yaml.safe_load(expectations_path.read_text())

    baseline = work_root / "baseline-render"
    ctx = render_fixture(manifest, 0, baseline)
    baseline_snapshot = snapshot(baseline)

    for name, expect in expectations.items():
        solution_dir = SOLUTIONS_DIR / fixture_id / name
        if not solution_dir.is_dir():
            failures.append(Failure(fixture_id, name, "solution directory missing"))
            continue
        trial = work_root / f"solution-{name}"
        render_fixture(manifest, 0, trial)
        trial_tofu = Tofu(trial, cache_dir=PROVIDER_CACHE, timeout_s=300)
        init_res = trial_tofu.init()
        if init_res.exit_code != 0:
            failures.append(Failure(fixture_id, name, f"tofu init failed: {init_res.stderr.strip()[-300:]}"))
            continue
        trial_tofu.apply()  # the initial, expected-to-fail apply (partial state)
        _overlay(solution_dir, trial)
        result = score_directory_apply(
            manifest, ctx, baseline, baseline_snapshot, trial, tofu=trial_tofu,
        )
        _cleanup(trial_tofu, name)
        failures.extend(_assert_expected(manifest, name, expect, result))
    return failures


def _selftest_generation(fixture_dir: Path, work_root: Path) -> list:
    """Generation selftest: score each reference module, assert the rubric ranks
    intentionally different good designs above every bad one (correct_alt at
    the quality level). Plan-only — creates no resources."""
    from .generation import GenerationFixture, score_generation

    fixture = GenerationFixture.load(fixture_dir)
    failures: list = []
    expectations_path = SOLUTIONS_DIR / fixture.id / "expectations.yaml"
    if not expectations_path.is_file():
        return [Failure(fixture.id, "solutions", f"missing {expectations_path}")]
    expectations = yaml.safe_load(expectations_path.read_text())

    scores: dict = {}
    for name, expect in expectations.items():
        ref_dir = SOLUTIONS_DIR / fixture.id / name
        if not ref_dir.is_dir():
            failures.append(Failure(fixture.id, name, "reference module missing"))
            continue
        # score a copy so plan artifacts never land in the repo
        module_copy = work_root / name / "module"
        shutil.copytree(ref_dir, module_copy)
        result = score_generation(fixture, module_copy, work_root / name / "work")
        scores[name] = result.semantic_score
        summary = f"gate={result.gate} score={result.semantic_score} items={result.items}"
        if result.gate != expect.get("gate", True):
            failures.append(Failure(fixture.id, name, f"expected gate={expect.get('gate', True)}: {summary}"))
            continue
        if "min_score" in expect and result.semantic_score < expect["min_score"]:
            failures.append(Failure(fixture.id, name, f"score below {expect['min_score']}: {summary} details={result.details}"))
        if "max_score" in expect and result.semantic_score > expect["max_score"]:
            failures.append(Failure(fixture.id, name, f"score above {expect['max_score']}: {summary}"))
        for item_id in expect.get("must_pass", []) or []:
            if not result.items.get(item_id, False):
                failures.append(Failure(fixture.id, name, f"expected {item_id} to pass: {summary} details={result.details}"))
        for item_id in expect.get("must_fail", []) or []:
            if result.items.get(item_id, False):
                failures.append(Failure(fixture.id, name, f"expected {item_id} to fail: {summary}"))
    return failures


def selftest_fixture(fixture_id: str, work_root: Path) -> list:
    failures: list = []
    fixture_dir = find_fixture_dir(fixture_id)
    work_root.mkdir(parents=True, exist_ok=True)

    if (fixture_dir / "rubric.yaml").is_file():
        if os.environ.get("IACBENCH_AWS") != "1":
            print("  skipped (generation scoring plans against AWS; set IACBENCH_AWS=1 to run)")
            return []
        return _selftest_generation(fixture_dir, work_root)

    manifest = FixtureManifest.load(fixture_dir)

    if manifest.tier == 2:
        if os.environ.get("IACBENCH_AWS") != "1":
            print("  skipped (tier 2 creates real cloud resources; set IACBENCH_AWS=1 to run)")
            return []
        return _selftest_tier2(manifest, work_root)

    # 1. determinism: same seed twice is byte-identical; a different seed differs
    failures.extend(_determinism_check(manifest, work_root))

    # 2. the fixture is genuinely broken, with the declared error class
    for seed in _BROKEN_SEEDS:
        d = work_root / f"broken-seed{seed}"
        render_fixture(manifest, seed, d)
        failures.extend(_broken_check(manifest, d, seed))

    # 3. solution matrix at seed 0
    expectations_path = SOLUTIONS_DIR / fixture_id / "expectations.yaml"
    if not expectations_path.is_file():
        failures.append(Failure(fixture_id, "solutions", f"missing {expectations_path}"))
        return failures
    expectations = yaml.safe_load(expectations_path.read_text())

    base = work_root / "base"
    ctx = render_fixture(manifest, 0, base)
    # Init may fail on fixtures broken at init time; scoring init's lazily.
    Tofu(base, cache_dir=PROVIDER_CACHE).init()
    baseline_snapshot = snapshot(base)

    for name, expect in expectations.items():
        solution_dir = SOLUTIONS_DIR / fixture_id / name
        if not solution_dir.is_dir():
            failures.append(Failure(fixture_id, name, "solution directory missing"))
            continue
        trial = work_root / f"solution-{name}"
        shutil.copytree(base, trial, symlinks=True)
        _overlay(solution_dir, trial)
        result = score_directory(
            manifest, ctx, base, baseline_snapshot, trial,
            tofu=Tofu(trial, cache_dir=PROVIDER_CACHE),
        )
        failures.extend(_assert_expected(manifest, name, expect, result))
    return failures


def run_selftest(fixture_ids=None) -> int:
    ids = fixture_ids or all_fixture_ids()
    if not ids:
        print("no fixtures found")
        return 1
    all_failures: list = []
    with tempfile.TemporaryDirectory(prefix="iacbench-selftest-") as tmp:
        for fid in ids:
            print(f"== {fid} ==", flush=True)
            failures = selftest_fixture(fid, Path(tmp) / fid)
            if failures:
                for f in failures:
                    print(f"  FAIL [{f.check}] {f.message}")
            else:
                print("  ok")
            all_failures.extend(failures)
    print()
    if all_failures:
        print(f"selftest FAILED: {len(all_failures)} failure(s) across {len(ids)} fixture(s)")
        return 1
    print(f"selftest passed: {len(ids)} fixture(s)")
    return 0
