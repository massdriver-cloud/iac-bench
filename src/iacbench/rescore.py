"""Re-score stored candidates with the current engine and compare against the
scores their eval logs recorded.

Every engine change is accepted on two checks: the known-answer selftest,
and this one, over real model output: each candidate module is scored again
and every gate, rubric item, expertise item and finding is compared with the
logged score for the same module (joined by module_sha, as the report joins
judge grades). Plans run against the fixture's cloud, as in scoring.
"""

from __future__ import annotations

import shutil
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from .artifacts import module_sha
from .generation import GenerationFixture, score_generation
from .report import collect_attempts


def _differences(logged, result) -> list:
    diffs = []
    if logged.gate != result.gate:
        diffs.append(f"gate {logged.gate} -> {result.gate}")
    before, after = logged.items or {}, result.items
    for k in sorted(set(before) | set(after)):
        a, b = before.get(k), after.get(k)
        if (a is None) != (b is None) or (a is not None and abs(float(a) - float(b)) > 1e-9):
            diffs.append(f"{k} {a} -> {b}")
    before, after = logged.expertise or {}, result.expertise
    for k in sorted(set(before) | set(after)):
        if bool(before.get(k)) != bool(after.get(k)):
            diffs.append(f"{k} {before.get(k)} -> {after.get(k)}")
    if sorted(logged.mandatory_failures or []) != sorted(result.mandatory_failures):
        diffs.append(f"findings {logged.mandatory_failures} -> {result.mandatory_failures}")
    return diffs


def run_rescore(
    fixture: GenerationFixture, candidates: Path, log_dir: Path, workers: int = 8,
    sha_map: dict | None = None,
) -> int:
    """Print every difference; 0 when every logged candidate scores as logged.
    Candidates without a logged score (hand-written references) are skipped.
    `sha_map` maps a redacted module's hash to the hash its score was logged
    under (a data release's redactions.json)."""
    logged = {
        a.module_sha: a
        for a in collect_attempts(log_dir)
        if a.fixture == fixture.id and a.module_sha
    }
    dirs = sorted(d for d in Path(candidates).iterdir() if d.is_dir())
    jobs = []
    for d in dirs:
        sha = module_sha(d)
        attempt = logged.get((sha_map or {}).get(sha, sha))
        if attempt is None:
            print(f"{d.name}: skipped, no logged score for this module in {log_dir}")
        else:
            jobs.append((d, attempt))

    def one(job):
        d, attempt = job
        work = Path(tempfile.mkdtemp(prefix="iacbench-rescore-"))
        try:
            shutil.copytree(d, work / "module")
            result = score_generation(fixture, work / "module", work / "probes")
        finally:
            shutil.rmtree(work, ignore_errors=True)
        solver = [line for line in result.details if line.startswith("solver:")]
        return d.name, _differences(attempt, result), solver

    changed = 0
    with ThreadPoolExecutor(workers) as pool:
        for name, diffs, solver in pool.map(one, jobs):
            if diffs:
                changed += 1
                print(f"{name}: {'; '.join(diffs)}")
                for line in solver:
                    print(f"    {line}")
    editions = sorted({a.rubric_sha or "unknown" for _, a in jobs})
    print(
        f"{len(jobs)} re-scored, {changed} differ "
        f"(logged rubric edition {', '.join(editions)}; current {fixture.rubric_sha})"
    )
    return 1 if changed else 0
