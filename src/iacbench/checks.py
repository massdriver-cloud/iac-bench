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


def _where_leaf_values(node, where: dict):
    """Static-source values at the leaf paths a where spec names, following
    nested blocks (lists of dicts) and `dynamic` blocks. A dynamic block's
    for_each is yielded too: it gates the block's existence, so a variable
    feeding it controls the behavior as surely as one feeding the leaf."""
    if isinstance(node, list):
        for item in node:
            yield from _where_leaf_values(item, where)
        return
    if not isinstance(node, dict):
        return
    for key, spec in where.items():
        leaf = not isinstance(spec, dict) or _is_leaf_predicate(spec)
        children = []
        if key in node:
            children.append(node[key])
        for dyn in node.get("dynamic", []) or []:
            if isinstance(dyn, dict) and key in dyn:
                block = dyn[key]
                if isinstance(block, dict):
                    if "for_each" in block:
                        yield block["for_each"]
                    children.append(block.get("content", {}))
        for child in children:
            if leaf:
                yield child
            else:
                yield from _where_leaf_values(child, spec)


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
    plans. quantifier: all|any over plans; match: any|every over instances.
    if_present: a plan without the type passes — for optional resources whose
    instances, when planned, must still match."""
    plans = _target_plans(ctx, spec.get("plans", "defaults"))
    if not plans:
        return False
    exists = spec.get("exists", True)
    where = spec.get("where")
    match = spec.get("match", "any")
    if_present = spec.get("if_present", False)

    def plan_ok(plan: dict) -> bool:
        insts = of_type(plan, spec["type"])
        if not insts:
            return if_present or not exists
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
    if isinstance(expected, dict) and "in" in expected:
        return value in expected["in"]
    return value == expected


_DYNAMIC = object()  # a dynamic block on the path: generated, never literal


def _path_values(node, path: list) -> list:
    """Every value at a dotted attribute path through nested blocks (parsed as
    lists of dicts). A `dynamic` block on the path yields _DYNAMIC; a path
    that leads nowhere yields [_MISSING]."""
    if not path:
        return [node]
    if isinstance(node, list):
        if not node:
            return [_MISSING]
        return [v for item in node for v in _path_values(item, path)]
    if not isinstance(node, dict):
        return [_MISSING]
    head, rest = path[0], path[1:]
    if rest and any(isinstance(d, dict) and head in d for d in node.get("dynamic", []) or []):
        return [_DYNAMIC]
    if head not in node:
        return [_MISSING]
    return _path_values(node[head], rest)


def _verb_hardcoded(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: the secure configuration is a property of the source, not
    a knob. When `attrs` are given, EVERY instance of `type` must carry them
    as literals equal to the required values — a single conditional instance
    with weaker or variable-fed values is a hidden knob and fails, even if a
    clean instance also exists. Additionally at least one instance must be
    existence-unconditional (no variable taint on count/for_each), so the
    protection cannot be gated off entirely. Conditional *secure* siblings
    (e.g. a prod-only log-bucket guard with the same literal values) pass.
    `attrs_exist` only requires attribute presence. Attribute names may be
    dotted paths through nested blocks (`settings.ip_configuration.ssl_mode`);
    every occurrence along the path must be literal, and a dynamic block on
    the path is a knob. An expected value of `{in: [...]}` accepts any
    listed literal (the same operator `where` uses)."""
    loc = hclq.locals_map(ctx.module_dir)
    attrs = spec.get("attrs") or {}
    attrs_exist = spec.get("attrs_exist") or []
    instances = hclq.resource_attrs(ctx.module_dir, spec["type"])
    def values(inst: dict, name: str) -> list:
        return _path_values(inst, name.split("."))

    if attrs and any(
        v is _DYNAMIC or not _is_literal(v, expected)
        for inst in instances
        for name, expected in attrs.items()
        for v in values(inst, name)
    ):
        return False
    for inst in instances:
        if not _instance_unconditional(inst, loc):
            continue
        if any(_MISSING in values(inst, name) for name in attrs_exist):
            continue
        if attrs and any(_MISSING in values(inst, name) for name in attrs):
            continue
        return True
    return False


def _verb_declares(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: the source declares at least one resource of `type`,
    whether or not anything gates its existence."""
    return bool(hclq.resource_attrs(ctx.module_dir, spec["type"]))


def _verb_expr_matches(ctx: CheckContext, spec: dict) -> bool:
    """Static lens over attribute expressions resolved through locals and
    data sources.
    match: every (default) — every resource of `type` has `attr` matching
    `pattern` or has `or_attr_present`; match: any — at least one resource's
    `attr` matches."""
    pattern = re.compile(spec["pattern"])
    insts = hclq.resource_attrs(ctx.module_dir, spec["type"])
    if not insts:
        return False
    fallback = spec.get("or_attr_present")
    if spec.get("match", "every") == "any":
        return any(
            spec["attr"] in inst
            and pattern.search(hclq.value_text_closure(ctx.module_dir, inst[spec["attr"]]))
            for inst in insts
        )
    for inst in insts:
        if spec["attr"] in inst:
            if not pattern.search(hclq.value_text_closure(ctx.module_dir, inst[spec["attr"]])):
                return False
        elif not (fallback and fallback in inst):
            return False
    return True


def _verb_var_feeds_attr(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: some declared variable (transitively through locals) feeds
    the named attribute. `has_default: true` restricts to optional variables —
    e.g. 'consumers can add tags without being forced to'. `type` restricts
    the search to one resource type; the attribute may sit in nested or
    dynamic blocks. `through_data: true` also follows data-source lookups
    keyed by a variable (off by default: a value *read from* a secret store
    is not the same as a value supplied as input)."""
    feeding = hclq.vars_feeding_attr(
        ctx.module_dir, spec["attr"], spec.get("type"), bool(spec.get("through_data"))
    )
    return _any_declared(ctx, feeding, spec.get("has_default"))


# Alternatives the perturbation sweep tries per input, beyond its current value.
SWEEP_ALTERNATIVES = 5


def _verb_closed_values(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: no input can weaken the setting. Every value the source
    can produce for each of `attrs`, on every instance of `type`, equals the
    required value (or is in `{in: [...]}`): a literal, or an expression
    whose every branch, input domain (a bool, or a validation confining the
    input to listed values) and map value is one — a choice between secure
    settings is a decision, not a knob. Any open value, a missing attribute
    or a `dynamic` block on the path fails it. As with `hardcoded`, at least
    one instance must exist unconditionally. Proven from the source by
    solve.possible_values, so it needs no sweep."""
    from . import solve

    module = solve.Module.load(ctx.module_dir)
    instances = [r for r in module.resources if r.mode == "resource" and r.type == spec["type"]]
    if not instances:
        return False
    for res in instances:
        for name, expected in (spec.get("attrs") or {}).items():
            for node in solve.attr_nodes(res.body, name.split(".")):
                if node is None or node is solve._MISSING_ATTR:
                    return False
                values = solve.possible_values(module, node)
                if values is None or not all(_is_literal(v, expected) for v in values):
                    return False
    return any(not solve.existence_open(module, res) for res in instances)


def _verb_var_feeds_provider_attr(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: some declared variable (transitively through locals) feeds
    the named attribute of a provider configuration block — e.g. a region
    input, or a tags input feeding default_tags. `provider` restricts the
    search to one provider; `has_default` as for var_feeds_attr."""
    feeding = hclq.vars_feeding_provider_attr(ctx.module_dir, spec["attr"], spec.get("provider"))
    return _any_declared(ctx, feeding, spec.get("has_default"))


def _any_declared(ctx: CheckContext, names: set, want_default) -> bool:
    declared = hclq.variables(ctx.module_dir)
    for name in names:
        meta = declared.get(name)
        if meta is None:
            continue
        if want_default is not None and meta["has_default"] != want_default:
            continue
        return True
    return False


_VER_RE = re.compile(r"v?(\d+)(?:\.\d+)*")


def _major(version: str) -> int | None:
    m = _VER_RE.fullmatch(version.strip())
    return int(m.group(1)) if m else None


def _constraint_bounded(constraint) -> bool:
    """True when a version constraint cannot admit an untested major jump:
    ~> bounds, = pins, and bare exact versions pass; a >=/> lower bound needs
    an upper bound within the NEXT major (>= 5.0, < 7.0 spans two majors and
    fails). A lone upper bound with no lower bound is accepted (rare, and
    there is no lower major to measure the window from)."""
    if not constraint or not isinstance(constraint, str) or "${" in constraint:
        return False
    lower = upper = None
    for part in constraint.split(","):
        part = part.strip()
        if part.startswith("~>") or part.startswith("="):
            return True
        if re.fullmatch(r"v?\d+(\.\d+)*", part):
            return True
        if part.startswith(">="):
            lower = _major(part[2:])
        elif part.startswith(">"):
            lower = _major(part[1:])
        elif part.startswith("<="):
            upper = _major(part[2:])
        elif part.startswith("<"):
            upper = _major(part[1:])
    if upper is None:
        return False
    if lower is None:
        return True
    # "< X.0" admits majors up to X-1; the window is tight iff upper <= lower+1
    return upper <= lower + 1


def _verb_provider_constraints(ctx: CheckContext, spec: dict) -> bool:
    """Hybrid lens: required_providers is declared, every declared constraint
    excludes an untested major jump — and every provider the defaults plan
    actually uses appears in the declarations, so omitting a provider from
    required_providers is a failure, never an escape."""
    providers = hclq.required_providers(ctx.module_dir)
    if not providers:
        return False
    if not all(_constraint_bounded(v) for v in providers.values()):
        return False
    if ctx.defaults_plan:
        declared = set(providers)
        for res in planned(ctx.defaults_plan):
            full = str(res.get("provider_name") or "")
            if "/builtin/" in full:
                continue  # terraform_data and friends: built in, never declarable
            name = full.rsplit("/", 1)[-1]
            if name and name not in declared:
                return False
    return True


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


def _verb_provider_config_attr(ctx: CheckContext, spec: dict) -> bool:
    """Static lens: some provider configuration block declares `attr`
    (e.g. default_tags on a standalone module's aws provider)."""
    return any(spec["attr"] in attrs for _name, attrs in hclq.provider_blocks(ctx.module_dir))


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
    if spec.get("require_descriptions"):
        # Fail-safe: a file the static lens cannot parse could hide
        # undescribed variables — an unparseable module never passes.
        if hclq.unparsed_files(ctx.module_dir):
            return False
        if any(not m.get("has_description") for m in declared.values()):
            return False
        outputs = hclq.outputs(ctx.module_dir)
        if any(not str(s.get("description") or "").strip() for s in outputs.values()):
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
    "declares": _verb_declares,
    "var_feeds_attr": _verb_var_feeds_attr,
    "closed_values": _verb_closed_values,
    "provider_constraints": _verb_provider_constraints,
    "provider_config_attr": _verb_provider_config_attr,
    "var_feeds_provider_attr": _verb_var_feeds_provider_attr,
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


def grade_ladder(ctx, rungs: list) -> float:
    """Graded alternatives: the score of the best rung whose check passes, 0
    when none does. Rungs: [{score: 1.0, check: ...}, {score: 0.5, check: ...}]."""
    return max((float(r["score"]) for r in rungs if evaluate(ctx, r["check"])), default=0.0)


def grade_budget(ctx: CheckContext, spec: dict) -> float:
    """The graded `budget` posture: full credit at or under `soft` declared
    variables, falling linearly to zero at `hard` (soft 10 / hard 15 loses
    20% per variable past 10)."""
    soft, hard = spec["soft"], spec["hard"]
    n = len(hclq.variables(ctx.module_dir))
    if n <= soft:
        return 1.0
    if n >= hard:
        return 0.0
    return 1.0 - (n - soft) / (hard - soft)


def grade_default_on(
    ctx: CheckContext, spec: dict, partial: float = 0.5, hardcoded_on: float = 0.0
) -> float:
    """The graded `default_on` posture ladder (docs/generation-check-engine.md):
    1.0 = present at defaults with variable influence (an opt-out exists);
    partial = opt-in only (absent at defaults, reachable through the sweep);
    0.0 = absent everywhere, or hardcoded in either polarity.
    `hardcoded_on` credits present-at-defaults with no opt-out, for
    protections where always-on costs flexibility but blocks nothing.
    A list of behaviors is alternative mechanisms for the same protection;
    the best-graded one counts."""
    if isinstance(spec, list):
        return max(
            (grade_default_on(ctx, s, partial, hardcoded_on) for s in spec), default=0.0
        )
    behavior = dict(spec)
    behavior.pop("plans", None)
    behavior.pop("quantifier", None)
    at_defaults = _verb_resource(ctx, {**behavior, "plans": "defaults"})
    if at_defaults:
        loc = hclq.locals_map(ctx.module_dir)
        # An opt-out exists when a variable gates the resource's existence, or
        # feeds the exact attribute path the behavior is defined by (`where`
        # leaves) — unrelated var-fed attributes (tags = var.tags, or a
        # sibling setting in the same nested block) prove nothing.
        where = spec.get("where") or {}
        for inst in hclq.resource_attrs(ctx.module_dir, spec["type"]):
            if not _instance_unconditional(inst, loc):
                return 1.0
            for value in _where_leaf_values(inst, where):
                if hclq._var_closure(loc, value):
                    return 1.0
        return float(hardcoded_on)  # hardcoded-on: no opt-out
    if _verb_resource(ctx, {**behavior, "plans": "sweep", "quantifier": "any"}):
        return float(partial)
    return 0.0
