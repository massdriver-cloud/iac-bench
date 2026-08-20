"""Mechanical invariants I1–I5.

Every verdict is computed from tofu exit codes, plan JSON, and file diffs —
never from comparison against a stored correct answer. All five invariants are
computed even after one fails; the per-invariant breakdown is what makes
failures diagnosable.

I3, I4, and I5 exist to defeat degenerate solutions: deleting the offending
resource, commenting out config, or emptying a file all make `plan` succeed.
"""

from __future__ import annotations

import difflib
import fnmatch
import hashlib
import re
import tempfile
from dataclasses import dataclass, field
from pathlib import Path

from .manifest import FixtureManifest
from .render import render_address
from .tofu import Tofu

INVARIANT_KEYS = {
    "I1": "I1_validate_exit_zero",
    "I2": "I2_plan_exit_zero",
    "I3": "I3_required_addresses_present",
    "I4": "I4_no_expected_resources_removed",
    "I5": "I5_no_forbidden_file_edits",
}

APPLY_INVARIANT_KEYS = {
    "A1": "A1_validate_exit_zero",
    "A2": "A2_apply_exit_zero",
    "A3": "A3_required_addresses_in_state",
    "A4": "A4_no_expected_resources_removed",
    "A5": "A5_no_forbidden_file_edits",
    "A6": "A6_no_drift_after_apply",
}

_RESOURCE_RE = re.compile(
    r'^\s*resource\s+"([A-Za-z0-9_-]+)"\s+"([A-Za-z0-9_-]+)"', re.MULTILINE
)
_SNAPSHOT_SKIP_DIRS = {".terraform"}
# State files are harness-managed; they must never count as model edits.
_SNAPSHOT_SKIP_NAMES = {"terraform.tfstate", "terraform.tfstate.backup", ".terraform.tfstate.lock.info"}


def snapshot(dir_path: Path) -> dict:
    """Map of relpath -> sha256 for all files, skipping .terraform/ and plan files."""
    result: dict = {}
    dir_path = Path(dir_path)
    for p in sorted(dir_path.rglob("*")):
        if not p.is_file():
            continue
        rel = p.relative_to(dir_path)
        if rel.parts[0] in _SNAPSHOT_SKIP_DIRS or rel.suffix == ".tfplan" or rel.name in _SNAPSHOT_SKIP_NAMES:
            continue
        result[rel.as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return result


def base_address(addr: str) -> str:
    """Strip a trailing instance key: null_resource.a["x"] -> null_resource.a."""
    return re.sub(r"\[[^\]]*\]$", "", addr)


def declared_addresses(dir_path: Path) -> set:
    """type.name addresses declared in *.tf files (textual parse of the baseline)."""
    found = set()
    for tf in sorted(Path(dir_path).rglob("*.tf")):
        if ".terraform" in tf.parts:
            continue
        for m in _RESOURCE_RE.finditer(tf.read_text(errors="replace")):
            found.add(f"{m.group(1)}.{m.group(2)}")
    return found


def matches_forbidden(relpath: str, patterns) -> bool:
    for pat in patterns:
        if fnmatch.fnmatch(relpath, pat):
            return True
        # fnmatch has no ** semantics; let "**/x" also match top-level "x"
        if pat.startswith("**/") and fnmatch.fnmatch(relpath, pat[3:]):
            return True
    return False


def _module_addresses(root_module: dict) -> list:
    addresses: list = []

    def walk(module: dict) -> None:
        for res in module.get("resources") or []:
            addresses.append(res["address"])
        for child in module.get("child_modules") or []:
            walk(child)

    walk(root_module or {})
    return addresses


def planned_resource_addresses(plan_json: dict) -> list:
    return _module_addresses((plan_json.get("planned_values") or {}).get("root_module"))


def state_resource_addresses(state_json: dict) -> list:
    """Managed resource addresses in state (data sources excluded)."""
    addresses = _module_addresses((state_json.get("values") or {}).get("root_module"))
    return [a for a in addresses if not a.startswith("data.")]


@dataclass
class CheckResult:
    invariants: dict
    verdict: str
    failure_detail: str | None
    efficiency: dict
    planned_addresses: list = field(default_factory=list)

    @property
    def passed(self) -> bool:
        return self.verdict == "pass"


def _tail(text: str, lines: int = 15) -> str:
    return "\n".join(text.strip().splitlines()[-lines:])


def _diff_stats(baseline_dir: Path, work_dir: Path, changed: list) -> tuple:
    added = removed = 0
    for rel in changed:
        old_path = baseline_dir / rel
        new_path = work_dir / rel
        old = old_path.read_text(errors="replace").splitlines() if old_path.is_file() else []
        new = new_path.read_text(errors="replace").splitlines() if new_path.is_file() else []
        for line in difflib.unified_diff(old, new, lineterm=""):
            if line.startswith("+") and not line.startswith("+++"):
                added += 1
            elif line.startswith("-") and not line.startswith("---"):
                removed += 1
    return added, removed


def score_directory(
    manifest: FixtureManifest,
    ctx: dict,
    baseline_dir: Path,
    baseline_snapshot: dict,
    work_dir: Path,
    blocked_write_attempts: int = 0,
    tofu: Tofu | None = None,
) -> CheckResult:
    """Run all five invariants against work_dir (which must already be init'd)."""
    baseline_dir = Path(baseline_dir)
    work_dir = Path(work_dir)
    tofu = tofu or Tofu(work_dir)
    inv: dict = {}
    detail: list = []

    # Fixtures broken at init time (init validates config before installing
    # providers) can only be init'd after the fix; a failed init here simply
    # leaves validate to report the error.
    tofu.ensure_init()

    # I1 — validate exits zero
    validate_res = tofu.validate()
    inv[INVARIANT_KEYS["I1"]] = validate_res.exit_code == 0
    if validate_res.exit_code != 0:
        detail.append(f"validate exit {validate_res.exit_code}: {_tail(validate_res.stderr)}")

    # I2 — plan exits zero
    plan_json = None
    with tempfile.TemporaryDirectory(prefix="iacbench-plan-") as td:
        plan_file = Path(td) / "plan.tfplan"
        plan_res = tofu.plan(out_file=plan_file)
        inv[INVARIANT_KEYS["I2"]] = plan_res.exit_code == 0
        if plan_res.exit_code != 0:
            detail.append(f"plan exit {plan_res.exit_code}: {_tail(plan_res.stderr)}")
        else:
            plan_json = tofu.show_json(plan_file)
            if plan_json is None:
                detail.append("plan succeeded but plan JSON could not be read")

    planned = planned_resource_addresses(plan_json) if plan_json else []
    planned_bases = {base_address(a) for a in planned}

    # I3 — required addresses present in the planned resource set
    required = [base_address(render_address(a, ctx)) for a in manifest.required_addresses]
    missing_required = sorted(a for a in required if a not in planned_bases)
    inv[INVARIANT_KEYS["I3"]] = plan_json is not None and not missing_required
    if missing_required:
        detail.append(f"required addresses missing from plan: {', '.join(missing_required)}")

    # I4 — no expected resources removed
    removable = {base_address(render_address(a, ctx)) for a in manifest.removable_addresses}
    original = declared_addresses(baseline_dir) - removable
    missing_original = sorted(a for a in original if a not in planned_bases)
    count_ok = len(planned) >= manifest.min_resource_count
    inv[INVARIANT_KEYS["I4"]] = plan_json is not None and count_ok and not missing_original
    if plan_json is not None and not count_ok:
        detail.append(f"planned resource count {len(planned)} < min {manifest.min_resource_count}")
    if missing_original:
        detail.append(f"original resources removed: {', '.join(missing_original)}")

    # I5 — no forbidden file edits
    final_snapshot = snapshot(work_dir)
    changed = sorted(
        rel
        for rel in set(baseline_snapshot) | set(final_snapshot)
        if baseline_snapshot.get(rel) != final_snapshot.get(rel)
    )
    forbidden_touched = [rel for rel in changed if matches_forbidden(rel, manifest.forbidden_file_edits)]
    inv[INVARIANT_KEYS["I5"]] = not forbidden_touched and blocked_write_attempts == 0
    if forbidden_touched:
        detail.append(f"forbidden files modified: {', '.join(forbidden_touched)}")
    if blocked_write_attempts:
        detail.append(f"blocked write attempts: {blocked_write_attempts}")

    added, removed_lines = _diff_stats(baseline_dir, work_dir, changed)
    verdict = "pass" if all(inv.values()) else "fail"
    return CheckResult(
        invariants=inv,
        verdict=verdict,
        failure_detail="; ".join(detail) if detail else None,
        efficiency={
            "diff_lines_added": added,
            "diff_lines_removed": removed_lines,
            "files_touched": len(changed),
            "tofu_invocations": tofu.invocations,
        },
        planned_addresses=planned,
    )


def score_directory_apply(
    manifest: FixtureManifest,
    ctx: dict,
    baseline_dir: Path,
    baseline_snapshot: dict,
    work_dir: Path,
    blocked_write_attempts: int = 0,
    tofu: Tofu | None = None,
) -> CheckResult:
    """Tier-2 invariants A1–A6 for apply-level fixtures.

    The caller is responsible for cleanup (`tofu destroy`) after scoring —
    scoring itself must leave state intact so a re-score is possible.
    """
    baseline_dir = Path(baseline_dir)
    work_dir = Path(work_dir)
    tofu = tofu or Tofu(work_dir)
    inv: dict = {}
    detail: list = []

    tofu.ensure_init()

    # A1 — validate exits zero
    validate_res = tofu.validate()
    inv[APPLY_INVARIANT_KEYS["A1"]] = validate_res.exit_code == 0
    if validate_res.exit_code != 0:
        detail.append(f"validate exit {validate_res.exit_code}: {_tail(validate_res.stderr)}")

    # A2 — apply exits zero (idempotent re-apply if the model already applied)
    apply_res = tofu.apply()
    inv[APPLY_INVARIANT_KEYS["A2"]] = apply_res.exit_code == 0
    if apply_res.exit_code != 0:
        detail.append(f"apply exit {apply_res.exit_code}: {_tail(apply_res.stderr)}")

    state_json = tofu.show_state_json()
    in_state = state_resource_addresses(state_json) if state_json else []
    state_bases = {base_address(a) for a in in_state}

    # A3 — required addresses present in state
    required = [base_address(render_address(a, ctx)) for a in manifest.required_addresses]
    missing_required = sorted(a for a in required if a not in state_bases)
    inv[APPLY_INVARIANT_KEYS["A3"]] = state_json is not None and not missing_required
    if missing_required:
        detail.append(f"required addresses missing from state: {', '.join(missing_required)}")

    # A4 — no expected resources removed
    removable = {base_address(render_address(a, ctx)) for a in manifest.removable_addresses}
    original = declared_addresses(baseline_dir) - removable
    missing_original = sorted(a for a in original if a not in state_bases)
    count_ok = len(in_state) >= manifest.min_resource_count
    inv[APPLY_INVARIANT_KEYS["A4"]] = state_json is not None and count_ok and not missing_original
    if state_json is not None and not count_ok:
        detail.append(f"state resource count {len(in_state)} < min {manifest.min_resource_count}")
    if missing_original:
        detail.append(f"original resources removed: {', '.join(missing_original)}")

    # A5 — no forbidden file edits
    final_snapshot = snapshot(work_dir)
    changed = sorted(
        rel
        for rel in set(baseline_snapshot) | set(final_snapshot)
        if baseline_snapshot.get(rel) != final_snapshot.get(rel)
    )
    forbidden_touched = [rel for rel in changed if matches_forbidden(rel, manifest.forbidden_file_edits)]
    inv[APPLY_INVARIANT_KEYS["A5"]] = not forbidden_touched and blocked_write_attempts == 0
    if forbidden_touched:
        detail.append(f"forbidden files modified: {', '.join(forbidden_touched)}")
    if blocked_write_attempts:
        detail.append(f"blocked write attempts: {blocked_write_attempts}")

    # A6 — empty plan after apply; the refresh makes the provider verify that
    # every resource in state actually exists in the cloud
    if inv[APPLY_INVARIANT_KEYS["A2"]]:
        drift_res = tofu.plan_detailed()
        inv[APPLY_INVARIANT_KEYS["A6"]] = drift_res.exit_code == 0
        if drift_res.exit_code != 0:
            detail.append(f"post-apply plan not empty (exit {drift_res.exit_code}): {_tail(drift_res.stderr or drift_res.stdout)}")
    else:
        inv[APPLY_INVARIANT_KEYS["A6"]] = False

    added, removed_lines = _diff_stats(baseline_dir, work_dir, changed)
    verdict = "pass" if all(inv.values()) else "fail"
    return CheckResult(
        invariants=inv,
        verdict=verdict,
        failure_detail="; ".join(detail) if detail else None,
        efficiency={
            "diff_lines_added": added,
            "diff_lines_removed": removed_lines,
            "files_touched": len(changed),
            "tofu_invocations": tofu.invocations,
        },
        planned_addresses=in_state,
    )
