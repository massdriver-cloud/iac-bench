"""Generation-domain scoring (G-fixtures): functional gate + brief-specific rubric.

Plan-only: nothing is ever applied. Probes instantiate the module in throwaway
root configs written as .tf.json, run `tofu plan`, and inspect plan JSON.
The perturbation sweep discovers which documented input controls which behavior
without prescribing variable names — any well-designed interface passes.

Rubric items are declared in the fixture's rubric.yaml; their implementations
live in the check registry here, keyed by item id. Generic interface stats are
recorded but never weighted (see docs/generation-eval-design.md).
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from . import hclq
from .paths import PROVIDER_CACHE
from .tofu import Tofu

_ENVIRONMENTS = ["dev", "staging", "prod"]


@dataclass
class GenerationFixture:
    id: str
    domain: str
    suite_version: str
    tier: int
    scoring_policy: str
    mandatory: list
    items: list  # [{id, weight, method, description}]
    expertise: list  # [{id, description, discovered_via}] — unweighted checklist
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
            scoring_policy=data.get("scoring_policy", "v0"),
            mandatory=data.get("mandatory", []),
            items=data["items"],
            expertise=data.get("expertise", []),
            path=fixture_dir,
        )

    @property
    def brief(self) -> str:
        return (self.path / "brief.md").read_text()


@dataclass
class GenerationResult:
    gate: bool
    items: dict
    semantic_score: float
    details: list
    stats: dict
    scoring_policy: str
    probe_plans: int = 0
    # Expertise checklist: discovered service-specific touches, present/absent.
    # A separate subscore — never folded into semantic_score.
    expertise: dict = field(default_factory=dict)
    expertise_score: float | None = None
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


# ---------------------------------------------------------------- plan helpers

def _walk_resources(module: dict, out: list) -> None:
    for res in module.get("resources") or []:
        out.append(res)
    for child in module.get("child_modules") or []:
        _walk_resources(child, out)


def planned(plan_json: dict) -> list:
    out: list = []
    _walk_resources((plan_json.get("planned_values") or {}).get("root_module") or {}, out)
    return out


def of_type(plan_json: dict, rtype: str) -> list:
    return [r for r in planned(plan_json) if r.get("type") == rtype and r.get("mode") != "data"]


def pab_ok(plan_json: dict) -> bool:
    """At least one public access block exists and every one is fully enabled."""
    pabs = of_type(plan_json, "aws_s3_bucket_public_access_block")
    if not pabs:
        return False
    keys = ("block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets")
    return all(all((p.get("values") or {}).get(k) is True for k in keys) for p in pabs)


def sse_ok(plan_json: dict) -> bool:
    if of_type(plan_json, "aws_s3_bucket_server_side_encryption_configuration"):
        return True
    return any(
        (b.get("values") or {}).get("server_side_encryption_configuration")
        for b in of_type(plan_json, "aws_s3_bucket")
    )


def versioning_enabled(plan_json: dict) -> bool:
    for v in of_type(plan_json, "aws_s3_bucket_versioning"):
        cfg = (v.get("values") or {}).get("versioning_configuration") or []
        if any((c or {}).get("status") == "Enabled" for c in cfg):
            return True
    return False


def logging_present(plan_json: dict) -> bool:
    return bool(of_type(plan_json, "aws_s3_bucket_logging"))


def transition_days(plan_json: dict) -> tuple:
    days = set()
    for lc in of_type(plan_json, "aws_s3_bucket_lifecycle_configuration"):
        for rule in (lc.get("values") or {}).get("rule") or []:
            for tr in (rule or {}).get("transition") or []:
                if isinstance((tr or {}).get("days"), (int, float)):
                    days.add(int(tr["days"]))
    return tuple(sorted(days))


def noncurrent_handled(plan_json: dict) -> bool:
    for lc in of_type(plan_json, "aws_s3_bucket_lifecycle_configuration"):
        for rule in (lc.get("values") or {}).get("rule") or []:
            if (rule or {}).get("noncurrent_version_expiration") or (rule or {}).get("noncurrent_version_transition"):
                return True
    return False


def lifecycle_present(plan_json: dict) -> bool:
    for lc in of_type(plan_json, "aws_s3_bucket_lifecycle_configuration"):
        for rule in (lc.get("values") or {}).get("rule") or []:
            rule = rule or {}
            if rule.get("transition") or rule.get("expiration") or rule.get("noncurrent_version_expiration") or rule.get("noncurrent_version_transition"):
                return True
    return False


def multipart_hygiene(plan_json: dict) -> bool:
    for lc in of_type(plan_json, "aws_s3_bucket_lifecycle_configuration"):
        for rule in (lc.get("values") or {}).get("rule") or []:
            if (rule or {}).get("abort_incomplete_multipart_upload"):
                return True
    return False


def bucket_tags(plan_json: dict) -> list:
    return [(b.get("values") or {}).get("tags") or {} for b in of_type(plan_json, "aws_s3_bucket")]


def bucket_names(plan_json: dict) -> list:
    return [(b.get("values") or {}).get("bucket") for b in of_type(plan_json, "aws_s3_bucket")]


def _module_source_contains(module_dir: Path, needle: str) -> bool:
    for tf in Path(module_dir).rglob("*.tf"):
        if ".terraform" in tf.parts:
            continue
        if needle in tf.read_text(errors="replace"):
            return True
    return False


def bucket_policies_text(plan_json: dict) -> str:
    """Concatenated planned policy documents of all bucket policies."""
    parts = []
    for p in of_type(plan_json, "aws_s3_bucket_policy"):
        policy = (p.get("values") or {}).get("policy")
        if isinstance(policy, str):
            parts.append(policy)
    return " ".join(parts)


def ownership_enforced(plan_json: dict) -> bool:
    for oc in of_type(plan_json, "aws_s3_bucket_ownership_controls"):
        for rule in (oc.get("values") or {}).get("rule") or []:
            if (rule or {}).get("object_ownership") == "BucketOwnerEnforced":
                return True
    return False


def intelligent_tiering(plan_json: dict) -> bool:
    if of_type(plan_json, "aws_s3_bucket_intelligent_tiering_configuration"):
        return True
    for lc in of_type(plan_json, "aws_s3_bucket_lifecycle_configuration"):
        for rule in (lc.get("values") or {}).get("rule") or []:
            for tr in (rule or {}).get("transition") or []:
                if (tr or {}).get("storage_class") == "INTELLIGENT_TIERING":
                    return True
    return False


_UNIQUENESS_RE = re.compile(r"random_(id|string|pet|uuid|integer)\.|aws_caller_identity|bucket_prefix")


def bucket_names_unique_ok(module_dir: Path) -> bool:
    """Every bucket's name expression (seen through locals) includes a
    uniqueness source — the model knows the S3 namespace is global."""
    buckets = hclq.resource_attrs(module_dir, "aws_s3_bucket")
    if not buckets:
        return False
    for attrs in buckets:
        source = attrs.get("bucket", attrs.get("bucket_prefix"))
        if source is None:
            return False
        # bucket_prefix delegates uniqueness to AWS itself — acceptable
        if "bucket" not in attrs:
            continue
        text = hclq.value_text_closure(module_dir, attrs["bucket"])
        if not _UNIQUENESS_RE.search(text):
            return False
    return True


# ---------------------------------------------------------------- probe engine

@dataclass
class ProbeRun:
    var: str
    value: object
    ok: bool
    plan_json: dict | None


class ProbeHarness:
    """Instantiates the module in throwaway .tf.json roots and plans them."""

    def __init__(self, module_dir: Path, work_root: Path, timeout_s: int = 180):
        self.module_dir = Path(module_dir).resolve()
        self.work_root = Path(work_root).resolve()
        self.timeout_s = timeout_s
        self.plans_run = 0
        self._n = 0

    def plan_with(self, inputs: dict) -> tuple:
        """(exit_ok, plan_json|None) for one instantiation."""
        self._n += 1
        probe_dir = self.work_root / f"probe-{self._n:02d}"
        probe_dir.mkdir(parents=True, exist_ok=True)
        source = os.path.relpath(self.module_dir, probe_dir)
        (probe_dir / "main.tf.json").write_text(
            json.dumps(
                {
                    "provider": {"aws": {"region": "us-east-1"}},
                    "module": {"under_test": {"source": source, **inputs}},
                },
                indent=1,
            )
        )
        tofu = Tofu(probe_dir, cache_dir=PROVIDER_CACHE, timeout_s=self.timeout_s)
        if tofu.init().exit_code != 0:
            self.plans_run += 1
            return False, None
        plan_file = probe_dir / "probe.tfplan"
        res = tofu.plan(out_file=plan_file)
        self.plans_run += 1
        if res.exit_code != 0:
            return False, None
        return True, tofu.show_json(plan_file)


def example_inputs(example_dir: Path) -> dict:
    """Literal module-call inputs from the model's own example (expressions dropped)."""
    for doc in hclq.parse_dir(example_dir):
        for block in doc.get("module", []) or []:
            for _name, attrs in block.items():
                out = {}
                for k, v in (attrs or {}).items():
                    if k in ("source", "providers", "version"):
                        continue
                    if isinstance(v, str) and "${" in v:
                        continue
                    if isinstance(v, (str, int, float, bool, list, dict)):
                        out[k] = v
                return out
    return {}


def _candidates(name: str, current) -> list:
    if isinstance(current, bool):
        return [not current]
    if isinstance(current, (int, float)):
        return [int(current) + 60]
    if isinstance(current, str):
        if name == "environment":
            return [e for e in _ENVIRONMENTS if e != current][:1]
        if name == "team":
            return ["blue"]
        return [current + "2"]
    return []


# ---------------------------------------------------------------- scoring

def score_generation(fixture: GenerationFixture, module_dir: Path, work_root: Path) -> GenerationResult:
    # tofu resolves -out= paths against its own cwd; keep everything absolute
    module_dir = Path(module_dir).resolve()
    work_root = Path(work_root).resolve()
    work_root.mkdir(parents=True, exist_ok=True)
    details: list = []
    stats = hclq.stats(module_dir)

    # ---- Layer 1: functional gate — the module's own examples must plan
    example_plans: dict = {}
    gate = True
    for example in ("minimal", "prod"):
        ex_dir = module_dir / "examples" / example
        if not ex_dir.is_dir():
            gate = False
            details.append(f"gate: examples/{example} missing")
            continue
        tofu = Tofu(ex_dir, cache_dir=PROVIDER_CACHE, timeout_s=180)
        init_res = tofu.init()
        if init_res.exit_code != 0:
            gate = False
            details.append(f"gate: examples/{example} init failed: {init_res.stderr.strip()[-300:]}")
            continue
        plan_file = ex_dir / "gate.tfplan"
        res = tofu.plan(out_file=plan_file)
        if res.exit_code != 0:
            gate = False
            details.append(f"gate: examples/{example} plan failed: {res.stderr.strip()[-300:]}")
            continue
        example_plans[example] = tofu.show_json(plan_file)
        try:
            plan_file.unlink()
        except OSError:
            pass

    total_weight = sum(i["weight"] for i in fixture.items)
    if not gate or any(p is None for p in example_plans.values()):
        return GenerationResult(
            gate=False,
            items={i["id"]: False for i in fixture.items},
            semantic_score=0.0,
            details=details,
            stats=stats,
            scoring_policy=fixture.scoring_policy,
        )
    minimal_plan, prod_plan = example_plans["minimal"], example_plans["prod"]

    # ---- perturbation sweep (shared by all probe items)
    harness = ProbeHarness(module_dir, work_root / "probes")
    base_inputs = example_inputs(module_dir / "examples" / "prod")
    base_ok, base_plan = harness.plan_with(base_inputs)
    sweep: list = []
    if base_ok and base_plan:
        for var, current in base_inputs.items():
            for candidate in _candidates(var, current):
                ok, pj = harness.plan_with({**base_inputs, var: candidate})
                sweep.append(ProbeRun(var=var, value=candidate, ok=ok, plan_json=pj))
    else:
        details.append("probes: baseline instantiation from examples/prod did not plan")

    sweep_plans = [r.plan_json for r in sweep if r.ok and r.plan_json] + ([base_plan] if base_plan else [])

    # ---- check registry: volunteered-expertise items (scoring_policy v1).
    # Nothing here was asked for in the brief; presence checks measure what the
    # model knew to do on its own, and the perturbation sweep provides the
    # not-weakenable evidence for the mandatory security items.
    def h1() -> bool:
        return pab_ok(minimal_plan) and pab_ok(prod_plan)

    def h2() -> bool:
        static_clean = not hclq.attrs_var_tainted(
            module_dir,
            "aws_s3_bucket_public_access_block",
            ["block_public_acls", "block_public_policy", "ignore_public_acls", "restrict_public_buckets"],
        )
        return h1() and static_clean and all(pab_ok(p) for p in sweep_plans)

    def h3() -> bool:
        return sse_ok(minimal_plan) and sse_ok(prod_plan)

    def h4() -> bool:
        return h3() and all(sse_ok(p) for p in sweep_plans)

    def h5() -> bool:
        return bucket_names_unique_ok(module_dir)

    def h6() -> bool:
        return lifecycle_present(prod_plan)

    def h7() -> bool:
        return noncurrent_handled(prod_plan) or multipart_hygiene(prod_plan)

    def h8() -> bool:
        return versioning_enabled(prod_plan)

    def h9() -> bool:
        return logging_present(prod_plan)

    def h10() -> bool:
        return stats["variable_count"] <= 8

    def h11() -> bool:
        # No required input exists solely to feed tags. Multi-purpose inputs
        # (environment driving posture AND tags) and optional tag maps are fine;
        # a default-less variable whose only resource use is tagging is the sin.
        tag_vars = hclq.vars_feeding_attr(module_dir, "tags")
        other_vars = hclq.vars_feeding_attrs_except(module_dir, "tags")
        declared = hclq.variables(module_dir)
        tag_only_required = [
            v for v in tag_vars
            if v not in other_vars and not declared.get(v, {}).get("has_default", True)
        ]
        return not tag_only_required

    def h12() -> bool:
        # Informative tagging volunteered without demanding inputs for it.
        return h11() and any(t for t in bucket_tags(prod_plan))

    def h13() -> bool:
        # Promoted from expertise E3: logging must actually deliver — the log
        # destination grants the logging service write permission. Checked in
        # source, not plan JSON: policies interpolating resource ARNs are
        # unknown at plan time and invisible in planned values.
        return _module_source_contains(module_dir, "logging.s3.amazonaws.com")

    registry = {
        "H1": h1, "H2": h2, "H3": h3, "H4": h4, "H5": h5, "H6": h6,
        "H7": h7, "H8": h8, "H9": h9, "H10": h10, "H11": h11, "H12": h12,
        "H13": h13,
    }

    items: dict = {}
    passed_weight = 0
    for item in fixture.items:
        impl = registry.get(item["id"])
        if impl is None:
            items[item["id"]] = False
            details.append(f"{item['id']}: no check implementation registered")
            continue
        try:
            ok = bool(impl())
        except Exception as exc:
            ok = False
            details.append(f"{item['id']}: check error: {exc}")
        items[item["id"]] = ok
        if ok:
            passed_weight += item["weight"]
        else:
            details.append(f"{item['id']} FAIL: {item['description'].strip()}")

    score = passed_weight / total_weight if total_weight else 0.0
    mandatory_failures = [m for m in fixture.mandatory if not items.get(m, False)]

    # ---- expertise checklist: discovered service-specific touches. Presence
    # checks only — every item demands nothing from the consumer (no new
    # inputs, no assumed use-cases). Reported as its own subscore.
    expertise_checks = {
        "E1_ownership_controls": lambda: ownership_enforced(prod_plan),
        "E2_multipart_cleanup": lambda: multipart_hygiene(prod_plan),
        "E3_log_delivery_policy": lambda: "logging.s3.amazonaws.com" in bucket_policies_text(prod_plan),
        "E4_tls_enforcement": lambda: _module_source_contains(module_dir, "aws:SecureTransport"),
        "E5_regional_domain_output": lambda: any(
            "bucket_regional_domain_name" in v for v in hclq.outputs(module_dir).values()
        ),
        "E6_intelligent_tiering": lambda: intelligent_tiering(prod_plan),
    }
    declared_expertise = {item["id"] for item in fixture.expertise}
    expertise: dict = {}
    for key, check in expertise_checks.items():
        if declared_expertise and key not in declared_expertise:
            continue
        try:
            expertise[key] = bool(check())
        except Exception:
            expertise[key] = False
    expertise_score = (
        round(sum(expertise.values()) / len(expertise), 3) if expertise else None
    )

    return GenerationResult(
        expertise=expertise,
        expertise_score=expertise_score,
        mandatory_failures=mandatory_failures,
        gate=True,
        items=items,
        semantic_score=round(score, 3),
        details=details,
        stats=stats,
        scoring_policy=fixture.scoring_policy,
        probe_plans=harness.plans_run,
    )
