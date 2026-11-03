"""Selftest: validate the rubric checks against known-answer modules.

Each generation fixture ships a reference matrix under
testdata/solutions/<id>/: intentionally different good designs and targeted
bad ones, with expectations.yaml stating the gate, score bounds and the
items each must pass or fail. A misdeclared check breaks the matrix.
Scoring plans against the fixture's cloud, so this needs credentials.
"""

from __future__ import annotations

import os
import shutil
import tempfile
from dataclasses import dataclass
from pathlib import Path

import yaml

from .paths import SOLUTIONS_DIR, all_fixture_ids, find_fixture_dir


@dataclass
class Failure:
    fixture: str
    check: str
    message: str


# Environment variables any one of which signals usable provider credentials.
_CLOUD_CREDENTIAL_ENV = {
    "aws": ("AWS_ACCESS_KEY_ID", "AWS_PROFILE", "AWS_WEB_IDENTITY_TOKEN_FILE"),
    "gcp": ("GOOGLE_OAUTH_ACCESS_TOKEN", "GOOGLE_APPLICATION_CREDENTIALS", "GOOGLE_CREDENTIALS"),
    "azure": ("ARM_CLIENT_ID", "ARM_USE_CLI", "ARM_USE_MSI"),
}


def _has_cloud_credentials(cloud: str) -> bool:
    return any(os.environ.get(k) for k in _CLOUD_CREDENTIAL_ENV[cloud])


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
        # Graded (default_on) items report floats; full credit means >= 1.
        # Expertise items are asserted by the same lists.
        outcomes = {**result.items, **result.expertise}
        for item_id in expect.get("must_pass", []) or []:
            if float(outcomes.get(item_id, 0.0)) < 1.0:
                failures.append(Failure(fixture.id, name, f"expected {item_id} to pass: {summary} details={result.details}"))
        for item_id in expect.get("must_fail", []) or []:
            if float(outcomes.get(item_id, 0.0)) >= 1.0:
                failures.append(Failure(fixture.id, name, f"expected {item_id} to fail: {summary}"))
        # Exact values pin graded (default_on) ladder rungs.
        for item_id, want in (expect.get("items") or {}).items():
            if abs(float(result.items.get(item_id, -1.0)) - float(want)) > 1e-9:
                failures.append(Failure(fixture.id, name, f"expected {item_id}={want}: {summary}"))
    return failures


def selftest_fixture(fixture_id: str, work_root: Path) -> list:
    fixture_dir = find_fixture_dir(fixture_id)
    work_root.mkdir(parents=True, exist_ok=True)
    if os.environ.get("IACBENCH_CLOUD") != "1":
        print("  skipped (scoring plans against a real cloud; set IACBENCH_CLOUD=1 to run)")
        return []
    from .generation import GenerationFixture

    cloud = GenerationFixture.load(fixture_dir).cloud
    if not _has_cloud_credentials(cloud):
        print(f"  skipped (no {cloud} credentials in the environment)")
        return []
    return _selftest_generation(fixture_dir, work_root)


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
