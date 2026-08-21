"""Generation-domain scoring (G-fixtures): functional gate + declarative rubric.

The module is evaluated as a ROOT module at its own defaults — never wrapped
as a submodule, and never through the model's example input choices. The model
ships a minimal.tfvars(.json) with literal values for its required variables;
the harness filters it to required-only, plans once at defaults, then sweeps
the declared interface variable by variable. Rubric items are check specs in
the fixture's rubric.yaml, evaluated by the service-agnostic verb engine in
checks.py. See docs/generation-check-engine.md.

Plan-only: nothing is ever applied.
"""

from __future__ import annotations

import json
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from . import checks, hclq
from .artifacts import module_sha
from .paths import PROVIDER_CACHE
from .tofu import Tofu

# Harvested allowed-value lists (and fixture perturb hints) keep up to this
# many candidates so distant values like a "prod" tier stay reachable;
# type-derived perturbation stays at one candidate per variable.
_MAX_SWEEP_VALUES = 5
_TFVARS_NAMES = ("minimal.tfvars.json", "minimal.tfvars")


@dataclass
class GenerationFixture:
    id: str
    domain: str
    suite_version: str
    tier: int
    scoring_policy: str
    mandatory: list
    items: list  # [{id, weight, description, check | behavior, posture?, partial?}]
    expertise: list  # [{id, description, discovered_via, check}] — unweighted
    perturb: dict  # optional per-variable candidate hints for the sweep
    path: Path

    @classmethod
    def load(cls, fixture_dir: Path) -> GenerationFixture:
        fixture_dir = Path(fixture_dir)
        data = yaml.safe_load((fixture_dir / "rubric.yaml").read_text())
        return cls(
            id=data["id"],
            domain=data["domain"],
            suite_version=data["suite_version"],
            tier=data.get("tier", 2),
            scoring_policy=data.get("scoring_policy", "v1"),
            mandatory=data.get("mandatory", []),
            items=data["items"],
            expertise=data.get("expertise", []),
            perturb=data.get("perturb", {}) or {},
            path=fixture_dir,
        )

    @property
    def brief(self) -> str:
        return (self.path / "brief.md").read_text()


@dataclass
class GenerationResult:
    gate: bool
    items: dict  # id -> bool, or float for graded (default_on) items
    semantic_score: float
    details: list
    stats: dict
    scoring_policy: str
    probe_plans: int = 0
    # Content hash of the scored module — lets the report refuse to join this
    # score with a judge grade computed over a different artifact.
    module_sha: str | None = None
    # Expertise checklist: discovered service-specific touches, present/absent.
    # Reported as its own subscore; pooled with the rubric (at weight 1 per
    # item) into mechanical_score.
    expertise: dict = field(default_factory=dict)
    expertise_score: float | None = None
    # Rubric + expertise pooled into one weighted fraction — the mechanical
    # component of the composite. semantic_score stays rubric-only.
    mechanical_score: float | None = None
    # Mandatory (security) items that failed. Scores stay true — these are
    # reported as findings and fail the verdict instead of capping the number.
    mandatory_failures: list = field(default_factory=list)

    @property
    def verdict(self) -> str:
        return (
            "pass"
            if self.gate and self.semantic_score >= 0.8 and not self.mandatory_failures
            else "fail"
        )


# ---------------------------------------------------------------- probe engine

class RootProbeHarness:
    """Plans the module as a root module: one init, then repeated
    `tofu plan -var-file=<generated>.tfvars.json` runs in the same dir.
    Provider configuration comes from the environment (AWS_REGION, ambient
    credentials) — never injected."""

    def __init__(self, module_dir: Path, timeout_s: int = 180):
        self.module_dir = Path(module_dir).resolve()
        self.tofu = Tofu(self.module_dir, cache_dir=PROVIDER_CACHE, timeout_s=timeout_s)
        self.plans_run = 0
        self._n = 0

    def init(self):
        return self.tofu.init()

    def plan_with(self, inputs: dict) -> tuple:
        """(exit_ok, plan_json|None, stderr) for one instantiation."""
        self._n += 1
        var_file = self.module_dir / f"probe-{self._n:02d}.tfvars.json"
        var_file.write_text(json.dumps(inputs, indent=1))
        plan_file = self.module_dir / f"probe-{self._n:02d}.tfplan"
        try:
            res = self.tofu.plan(out_file=plan_file, var_file=var_file)
            self.plans_run += 1
            if res.exit_code != 0:
                return False, None, res.stderr
            return True, self.tofu.show_json(plan_file), ""
        finally:
            for p in (var_file, plan_file):
                try:
                    p.unlink()
                except OSError:
                    pass


# ---------------------------------------------------------------- sweep

_CONTAINS_RE = re.compile(r"contains\(\s*\[([^\]]*)\]")


def _allowed_values(meta: dict) -> list:
    """Candidate values harvested from `contains([...], var.x)` validations."""
    for condition in meta.get("validation_conditions", []):
        m = _CONTAINS_RE.search(condition)
        if not m:
            continue
        values = []
        for raw in m.group(1).split(","):
            raw = raw.strip().strip('"').strip("'")
            if not raw:
                continue
            try:
                values.append(json.loads(raw))
            except (ValueError, json.JSONDecodeError):
                values.append(raw)
        if values:
            return values
    return []


def _candidates(meta: dict, current) -> list:
    allowed = _allowed_values(meta)
    if allowed:
        return [v for v in allowed if v != current][:_MAX_SWEEP_VALUES]
    if isinstance(current, bool):
        return [not current]
    if isinstance(current, (int, float)):
        return [current + 60]
    if isinstance(current, str):
        return [current + "2"]
    if current is None:  # optional var defaulting to null, or untyped
        type_text = meta.get("type", "")
        if "bool" in type_text:
            return [True]
        if "number" in type_text:
            return [60]
        if "string" in type_text:
            return ["probe2"]
    return []  # lists/maps: no generic perturbation


# ---------------------------------------------------------------- scoring

def _find_tfvars(module_dir: Path) -> Path | None:
    for name in _TFVARS_NAMES:
        p = module_dir / name
        if p.is_file():
            return p
    return None


def _gate_failure(
    fixture: GenerationFixture, details: list, stats: dict, sha: str | None = None
) -> GenerationResult:
    return GenerationResult(
        gate=False,
        items={i["id"]: False for i in fixture.items},
        semantic_score=0.0,
        mechanical_score=0.0,
        details=details,
        stats=stats,
        scoring_policy=fixture.scoring_policy,
        module_sha=sha,
    )


def score_generation(fixture: GenerationFixture, module_dir: Path, work_root: Path) -> GenerationResult:
    module_dir = Path(module_dir).resolve()
    work_root = Path(work_root).resolve()
    work_root.mkdir(parents=True, exist_ok=True)
    details: list = []
    stats = hclq.stats(module_dir)
    sha = module_sha(module_dir)

    # Score against a copy: root-module planning writes .terraform/lockfile
    # into the module dir, and the candidate's directory stays pristine.
    work = work_root / "module"
    if work.exists():
        shutil.rmtree(work)
    shutil.copytree(module_dir, work, symlinks=True, ignore=shutil.ignore_patterns(".terraform"))

    # ---- Layer 1: functional gate — root module plans with its own tfvars,
    # filtered to required variables only (the defaults plan).
    # Contract: the task is authoring the module — calling out to remote
    # modules is answer-key evasion and fails the gate. Local submodules
    # (./ or ../ sources) are legitimate decomposition.
    remote = [s for s in hclq.module_sources(work) if not s.startswith(("./", "../"))]
    if remote:
        details.append(
            f"gate: calls remote module(s) instead of authoring resources: {', '.join(sorted(set(remote)))}"
        )
        return _gate_failure(fixture, details, stats, sha)
    tfvars_path = _find_tfvars(work)
    if tfvars_path is None:
        details.append("gate: no minimal.tfvars or minimal.tfvars.json at the module root")
        return _gate_failure(fixture, details, stats, sha)
    try:
        tfvars = hclq.parse_tfvars(tfvars_path)
    except Exception as exc:
        details.append(f"gate: could not parse {tfvars_path.name}: {exc}")
        return _gate_failure(fixture, details, stats, sha)

    varmeta = hclq.variables(work)
    required = {name for name, m in varmeta.items() if not m["has_default"]}
    missing = sorted(required - set(tfvars))
    if missing:
        details.append(f"gate: {tfvars_path.name} missing required variable(s): {', '.join(missing)}")
        return _gate_failure(fixture, details, stats, sha)
    # Optional values in the tfvars never reach the defaults plan — that would
    # smuggle the model's choices back into out-of-the-box posture.
    defaults_inputs = {name: tfvars[name] for name in sorted(required)}
    extra = sorted(set(tfvars) - required)
    if extra:
        details.append(f"note: {tfvars_path.name} sets optional variable(s) ignored by scoring: {', '.join(extra)}")

    harness = RootProbeHarness(work)
    init_res = harness.init()
    if init_res.exit_code != 0:
        details.append(f"gate: tofu init failed: {init_res.stderr.strip()[-300:]}")
        return _gate_failure(fixture, details, stats, sha)
    ok, defaults_plan, stderr = harness.plan_with(defaults_inputs)
    if not ok or defaults_plan is None:
        details.append(f"gate: defaults plan (required-only inputs) failed: {stderr.strip()[-300:]}")
        return _gate_failure(fixture, details, stats, sha)

    # ---- perturbation sweep: interface-driven — every declared variable,
    # perturbed from its default (or its tfvars value for required ones).
    # Candidates come from validation allowed-values, the value's type, or
    # fixture perturb hints. Failed plans are recorded and excluded: a
    # validation rejecting a candidate is good design, not a penalty.
    sweep_plans: list = []
    rejected = 0
    unswept: list = []
    for name, meta in sorted(varmeta.items()):
        base = defaults_inputs.get(name, meta["default"])
        candidates = fixture.perturb.get(name) or _candidates(meta, base)
        if not candidates:
            unswept.append(name)
            continue
        for candidate in candidates[:_MAX_SWEEP_VALUES]:
            ok, plan_json, _ = harness.plan_with({**defaults_inputs, name: candidate})
            if ok and plan_json:
                sweep_plans.append(plan_json)
            else:
                rejected += 1
    if rejected:
        details.append(f"sweep: {rejected} perturbation(s) rejected at plan time (excluded from evidence)")
    if unswept:
        # A capability offered only through these variables is invisible to
        # reachable-posture checks — surface the blind spot, never hide it.
        details.append(
            "sweep: no candidates for variable(s) (collection-typed or "
            f"unperturbable): {', '.join(unswept)} — reachable checks may under-report"
        )
    unparsed = hclq.unparsed_files(work)
    if unparsed:
        details.append(
            f"static lens: could not parse {', '.join(unparsed)} — static checks are blind to these files"
        )
    stats["unswept_variables"] = unswept
    stats["unparsed_tf_files"] = unparsed

    # ---- rubric items via the declarative engine
    ctx = checks.CheckContext(
        module_dir=work,
        defaults_plan=defaults_plan,
        sweep_plans=sweep_plans,
        item_specs={i["id"]: i.get("check") for i in fixture.items if i.get("check")},
    )
    items: dict = {}
    total_weight = sum(i["weight"] for i in fixture.items)
    passed_weight = 0.0
    for item in fixture.items:
        try:
            if item.get("posture") == "default_on":
                value = checks.grade_default_on(ctx, item["behavior"], item.get("partial", 0.5))
            else:
                value = evaluate_memo(ctx, item["id"], item["check"])
        except Exception as exc:
            value = False
            details.append(f"{item['id']}: check error: {exc}")
        items[item["id"]] = value
        passed_weight += item["weight"] * float(value)
        if float(value) < 1.0:
            details.append(f"{item['id']} FAIL: {item['description'].strip()}")

    score = passed_weight / total_weight if total_weight else 0.0
    mandatory_failures = [m for m in fixture.mandatory if float(items.get(m, 0.0)) < 1.0]

    # ---- expertise checklist: same verbs, separate unweighted subscore.
    expertise: dict = {}
    for entry in fixture.expertise:
        try:
            expertise[entry["id"]] = bool(checks.evaluate(ctx, entry["check"]))
        except Exception as exc:
            expertise[entry["id"]] = False
            details.append(f"{entry['id']}: expertise check error: {exc}")
    expertise_score = (
        round(sum(expertise.values()) / len(expertise), 3) if expertise else None
    )

    # Pooled mechanical score: rubric items at their rubric weights, expertise
    # items at weight 1 (unless overridden) — the rubric dominates by
    # construction, and growing the checklist cannot swamp it.
    exp_total = sum(e.get("weight", 1) for e in fixture.expertise)
    exp_passed = sum(e.get("weight", 1) for e in fixture.expertise if expertise.get(e["id"]))
    mech_denominator = total_weight + exp_total
    mechanical_score = (
        round((passed_weight + exp_passed) / mech_denominator, 3) if mech_denominator else 0.0
    )

    return GenerationResult(
        expertise=expertise,
        expertise_score=expertise_score,
        mechanical_score=mechanical_score,
        mandatory_failures=mandatory_failures,
        gate=True,
        items=items,
        semantic_score=round(score, 3),
        details=details,
        stats=stats,
        scoring_policy=fixture.scoring_policy,
        probe_plans=harness.plans_run,
        module_sha=sha,
    )


def evaluate_memo(ctx: checks.CheckContext, item_id: str, spec: dict) -> bool:
    """Evaluate an item's check with memoization so `ref` reuses results."""
    if item_id in ctx.item_results:
        return bool(ctx.item_results[item_id])
    result = checks.evaluate(ctx, spec)
    ctx.item_results[item_id] = result
    return result
