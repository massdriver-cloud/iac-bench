"""Declarative check engine for generation scoring.

Rubric items declare their checks in the fixture's rubric.yaml as parameters
to the small, closed vocabulary of verbs implemented here. Verbs are
service-agnostic — every service-specific detail (resource types, attribute
names, patterns) lives in fixture YAML, never in this engine. See
docs/generation-check-engine.md.

Two lenses:
  static — parsed HCL (hclq): how the code is WRITTEN (hardcoded literals,
           variable taint, interface shape, source text)
  plan   — plan JSON at module defaults and across the perturbation sweep:
           what the code DOES (resolved through locals/ternaries/dynamic)
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path

from . import hclq

_MISSING = object()


# ------------------------------------------------------------ plan JSON lens

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


def _present(value) -> bool:
    """`exists` semantics: key present, not null, not an empty container."""
    if value is _MISSING or value is None:
        return False
    if isinstance(value, (list, dict, str)):
        return len(value) > 0
    return True


_LEAF_OPS = {"exists", "nonempty", "in"}


def _is_leaf_predicate(spec) -> bool:
    return isinstance(spec, dict) and bool(spec) and set(spec) <= _LEAF_OPS


def _match_value(value, spec) -> bool:
    if _is_leaf_predicate(spec):
        if "exists" in spec and _present(value) != bool(spec["exists"]):
            return False
        if "nonempty" in spec and _present(value) != bool(spec["nonempty"]):
            return False
        if "in" in spec and value not in spec["in"]:
            return False
        return True
    if isinstance(spec, dict):
        if isinstance(value, dict):
            return _match_where(value, spec)
        if isinstance(value, list):  # plan JSON renders nested blocks as lists
            return any(isinstance(el, dict) and _match_where(el, spec) for el in value)
        return False
    return value == spec  # literal equality (bool/number/string/list)


def _where_keys(where: dict) -> set:
    """All key names appearing anywhere in a where spec (nested included)."""
    keys: set = set()
    for k, v in where.items():
        keys.add(k)
        if isinstance(v, dict) and not _is_leaf_predicate(v):
            keys |= _where_keys(v)
    return keys


def _match_where(values: dict, where: dict) -> bool:
    for key, spec in where.items():
        value = values.get(key, _MISSING)
        if _is_leaf_predicate(spec) and "exists" in spec and not spec["exists"]:
            if _present(value):
                return False
            continue
        if value is _MISSING:
            return False
        if not _match_value(value, spec):
            return False
    return True


# ------------------------------------------------------------ check context

@dataclass
class CheckContext:
    module_dir: Path
    defaults_plan: dict | None
    sweep_plans: list = field(default_factory=list)
    item_specs: dict = field(default_factory=dict)   # id -> check spec (for ref)
    item_results: dict = field(default_factory=dict)  # id -> bool (memo)
    _resolving: set = field(default_factory=set)      # ref cycle guard


def _target_plans(ctx: CheckContext, on) -> list:
    # The field is spelled `plans:` in YAML — an unquoted `on:` key parses as
    # boolean True under YAML 1.1, which silently breaks lookups.
    targets = on if isinstance(on, list) else [on or "defaults"]
    plans: list = []
    for t in targets:
        if t == "defaults" and ctx.defaults_plan:
            plans.append(ctx.defaults_plan)
        elif t == "sweep":
            plans.extend(ctx.sweep_plans)
        else:
            raise ValueError(f"unknown plan target {t!r} (expected 'defaults' or 'sweep')")
    return plans


# ------------------------------------------------------------ verbs

def _verb_resource(ctx: CheckContext, spec: dict) -> bool:
    """Plan lens: resources of `type` exist / match `where` across the target
    plans. quantifier: all|any over plans; match: any|every over instances."""
    plans = _target_plans(ctx, spec.get("plans", "defaults"))
    if not plans:
        return False
    exists = spec.get("exists", True)
    where = spec.get("where")
    match = spec.get("match", "any")

    def plan_ok(plan: dict) -> bool:
        insts = of_type(plan, spec["type"])
        if not insts:
            return not exists
        if not exists:
            return False
        if where is None:
            return True
        matched = [_match_where(i.get("values") or {}, where) for i in insts]
        return all(matched) if match == "every" else any(matched)

    results = [plan_ok(p) for p in plans]
    return any(results) if spec.get("quantifier", "all") == "any" else all(results)


def _instance_unconditional(attrs: dict, loc: dict) -> bool:
    """No variable (transitively through locals) gates this resource's existence."""
    for meta in ("count", "for_each"):
        if meta in attrs and hclq._var_closure(loc, attrs[meta]):
            return False
    return True


def _is_literal(value, expected) -> bool:
    if isinstance(value, str) and "${" in value:
        return False
    return value == expected


def _verb_hardcoded(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: the secure configuration is a property of the source, not
    a knob. When `attrs` are given, EVERY instance of `type` must carry them
    as literals equal to the required values — a single conditional instance
    with weaker or variable-fed values is a hidden knob and fails, even if a
    clean instance also exists. Additionally at least one instance must be
    existence-unconditional (no variable taint on count/for_each), so the
    protection cannot be gated off entirely. Conditional *secure* siblings
    (e.g. a prod-only log-bucket guard with the same literal values) pass.
    `attrs_exist` only requires attribute presence."""
    loc = hclq.locals_map(ctx.module_dir)
    attrs = spec.get("attrs") or {}
    attrs_exist = spec.get("attrs_exist") or []
    instances = hclq.resource_attrs(ctx.module_dir, spec["type"])
    if attrs and any(
        not _is_literal(inst.get(name, _MISSING), expected)
        for inst in instances
        for name, expected in attrs.items()
    ):
        return False
    for inst in instances:
        if not _instance_unconditional(inst, loc):
            continue
        if any(name not in inst for name in attrs_exist):
            continue
        if attrs and any(name not in inst for name in attrs):
            continue
        return True
    return False


def _verb_expr_matches(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: every resource of `type` has `attr` whose expression,
    resolved through locals, matches `pattern` — or has `or_attr_present`."""
    pattern = re.compile(spec["pattern"])
    insts = hclq.resource_attrs(ctx.module_dir, spec["type"])
    if not insts:
        return False
    fallback = spec.get("or_attr_present")
    for inst in insts:
        if spec["attr"] in inst:
            if not pattern.search(hclq.value_text_closure(ctx.module_dir, inst[spec["attr"]])):
                return False
        elif not (fallback and fallback in inst):
            return False
    return True


def _verb_no_single_purpose_required_var(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: no default-less variable exists solely to feed the named
    attribute. Multi-purpose inputs and optional variables are fine."""
    attr = spec["attr"]
    feeding = hclq.vars_feeding_attr(ctx.module_dir, attr)
    other = hclq.vars_feeding_attrs_except(ctx.module_dir, attr)
    declared = hclq.variables(ctx.module_dir)
    offenders = [
        v for v in feeding
        if v not in other and not declared.get(v, {}).get("has_default", True)
    ]
    return not offenders


def strip_comments(text: str) -> str:
    """Remove #, //, and /* */ comments (outside quoted strings), so a
    substring check cannot be satisfied by a comment mentioning the needle."""
    out: list = []
    i, n = 0, len(text)
    in_string = False
    while i < n:
        ch = text[i]
        if in_string:
            out.append(ch)
            if ch == "\\" and i + 1 < n:
                out.append(text[i + 1])
                i += 1
            elif ch == '"':
                in_string = False
        elif ch == '"':
            in_string = True
            out.append(ch)
        elif ch == "#" or text[i:i + 2] == "//":
            while i < n and text[i] != "\n":
                i += 1
            continue
        elif text[i:i + 2] == "/*":
            end = text.find("*/", i + 2)
            i = n if end == -1 else end + 2
            continue
        else:
            out.append(ch)
        i += 1
    return "".join(out)


def _verb_source_contains(ctx: CheckContext, spec) -> bool:
    needle = spec if isinstance(spec, str) else spec["needle"]
    for tf in Path(ctx.module_dir).rglob("*.tf"):
        if ".terraform" in tf.parts:
            continue
        if needle in strip_comments(tf.read_text(errors="replace")):
            return True
    return False


def _verb_output_named(ctx: CheckContext, spec: dict) -> bool:
    outputs = hclq.outputs(ctx.module_dir)
    if "name_matches" in spec:
        pattern = re.compile(spec["name_matches"])
        if not any(pattern.search(name) for name in outputs):
            return False
    if "value_contains" in spec:
        # Only the output's value expression counts — a description mentioning
        # the needle is documentation, not the output.
        values = [
            hclq.value_text(s.get("value", "")) for s in outputs.values()
        ]
        if not any(spec["value_contains"] in text for text in values):
            return False
    return bool(spec) and bool(outputs)


def _verb_interface(ctx: CheckContext, spec: dict) -> bool:
    declared = hclq.variables(ctx.module_dir)
    if "max_variables" in spec and len(declared) > spec["max_variables"]:
        return False
    return True


def _verb_ref(ctx: CheckContext, item_id: str) -> bool:
    if item_id in ctx.item_results:
        return bool(ctx.item_results[item_id])
    if item_id in ctx._resolving:
        raise ValueError(f"circular ref involving {item_id!r}")
    target = ctx.item_specs.get(item_id)
    if target is None:
        raise ValueError(f"ref to unknown item {item_id!r}")
    ctx._resolving.add(item_id)
    try:
        result = evaluate(ctx, target)
    finally:
        ctx._resolving.discard(item_id)
    ctx.item_results[item_id] = result
    return result


_VERBS = {
    "resource": _verb_resource,
    "hardcoded": _verb_hardcoded,
    "expr_matches": _verb_expr_matches,
    "no_single_purpose_required_var": _verb_no_single_purpose_required_var,
    "source_contains": _verb_source_contains,
    "output_named": _verb_output_named,
    "interface": _verb_interface,
    "ref": _verb_ref,
}


def evaluate(ctx: CheckContext, spec: dict) -> bool:
    """Evaluate one check spec: a single-key dict naming a verb or combinator."""
    if not isinstance(spec, dict) or len(spec) != 1:
        raise ValueError(f"check spec must be a single-key mapping, got: {spec!r}")
    (name, body), = spec.items()
    if name == "all_of":
        return all(evaluate(ctx, sub) for sub in body)
    if name == "any_of":
        return any(evaluate(ctx, sub) for sub in body)
    if name == "not":
        return not evaluate(ctx, body)
    verb = _VERBS.get(name)
    if verb is None:
        raise ValueError(f"unknown check verb {name!r}")
    return verb(ctx, body)


def grade_default_on(ctx: CheckContext, spec: dict, partial: float = 0.5) -> float:
    """The graded `default_on` posture ladder (docs/generation-check-engine.md):
    1.0 = present at defaults with variable influence (an opt-out exists);
    partial = opt-in only (absent at defaults, reachable through the sweep);
    0.0 = absent everywhere, or hardcoded in either polarity."""
    behavior = dict(spec)
    behavior.pop("plans", None)
    behavior.pop("quantifier", None)
    at_defaults = _verb_resource(ctx, {**behavior, "plans": "defaults"})
    if at_defaults:
        loc = hclq.locals_map(ctx.module_dir)
        # An opt-out exists when a variable gates the resource's existence, or
        # feeds one of the attributes the behavior is defined by (`where`
        # keys) — unrelated var-fed attributes (tags = var.tags) prove nothing.
        behavior_attrs = _where_keys(spec.get("where") or {})
        for inst in hclq.resource_attrs(ctx.module_dir, spec["type"]):
            if not _instance_unconditional(inst, loc):
                return 1.0
            for name, value in inst.items():
                if name in behavior_attrs and hclq._var_closure(loc, value):
                    return 1.0
        return 0.0  # hardcoded-on: inflexible, breaks legitimate opt-out
    if _verb_resource(ctx, {**behavior, "plans": "sweep", "quantifier": "any"}):
        return float(partial)
    return 0.0
