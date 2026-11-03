"""Solve-then-confirm: input values that reach a rubric goal, found from the
source and confirmed by one plan.

The perturbation sweep changes one variable at a time, so a capability whose
input the module guards with a second input (zone balancing that requires
three or more instances) never appears in it. The solver reads the module's
expression trees (tools/hclast), evaluates them over candidate inputs drawn
from the module's own constants, and searches for an assignment, fewest
changed inputs first, under which a goal resource plans and every variable
validation and precondition holds. The harness then plans that assignment;
only a plan that succeeds is evidence, and it joins the sweep plans.

The evaluator is deliberately partial. Anything it cannot model (resource
attributes, data sources, unimplemented functions) is UNKNOWN: a goal is
never proven through an unknown, and a guard that is unknown does not block
a witness, because the confirming plan decides.
"""

from __future__ import annotations

import copy
import itertools
import json
import math
import re
from dataclasses import dataclass, field
from pathlib import Path

from . import checks, hclast


class _Unknown:
    def __repr__(self) -> str:
        return "UNKNOWN"


UNKNOWN = _Unknown()

# Search bounds: assignments change at most this many input leaves, and the
# search stops after this many evaluations or witnesses per goal.
MAX_CHANGED = 3
MAX_EVALUATIONS = 20000
MAX_WITNESSES = 3


class EvalError(Exception):
    """The expression fails in OpenTofu too (bad index, wrong type)."""


# ------------------------------------------------------------ module model

@dataclass
class Variable:
    type: dict | None
    default: dict | None
    has_default: bool
    validations: list


@dataclass
class Resource:
    mode: str  # "resource" | "data"
    type: str
    name: str
    body: dict


@dataclass
class Module:
    variables: dict = field(default_factory=dict)
    locals: dict = field(default_factory=dict)
    resources: list = field(default_factory=list)
    output_conditions: list = field(default_factory=list)

    @classmethod
    def load(cls, module_dir: Path) -> Module:
        m = cls()
        for _, f in sorted(hclast.files(module_dir).items()):
            for blk in (f.get("body") or {}).get("blocks", []):
                labels, body = blk["labels"] or [], blk["body"]
                attrs = body["attributes"]
                if blk["type"] == "variable" and labels:
                    m.variables[labels[0]] = Variable(
                        type=attrs["type"]["expr"] if "type" in attrs else None,
                        default=attrs["default"]["expr"] if "default" in attrs else None,
                        has_default="default" in attrs,
                        validations=[
                            b["body"]["attributes"]["condition"]["expr"]
                            for b in body["blocks"]
                            if b["type"] == "validation" and "condition" in b["body"]["attributes"]
                        ],
                    )
                elif blk["type"] == "locals":
                    m.locals.update({k: a["expr"] for k, a in attrs.items()})
                elif blk["type"] in ("resource", "data") and len(labels) == 2:
                    m.resources.append(Resource(blk["type"], labels[0], labels[1], body))
                elif blk["type"] == "output":
                    m.output_conditions += _conditions(body, "precondition")
        return m


def _conditions(body: dict, kind: str) -> list:
    out = []
    for blk in body["blocks"]:
        if blk["type"] == kind and "condition" in blk["body"]["attributes"]:
            out.append(blk["body"]["attributes"]["condition"]["expr"])
        if blk["type"] == "lifecycle":
            out += _conditions(blk["body"], kind)
    return out


# ------------------------------------------------------------ evaluation

def _is_num(v) -> bool:
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def _eq(a, b) -> bool:
    if isinstance(a, bool) or isinstance(b, bool):
        return type(a) is type(b) and a == b
    if _is_num(a) and _is_num(b):
        return a == b
    if type(a) is not type(b):
        return False
    if isinstance(a, list):
        return len(a) == len(b) and all(_eq(x, y) for x, y in zip(a, b, strict=True))
    if isinstance(a, dict):
        return a.keys() == b.keys() and all(_eq(a[k], b[k]) for k in a)
    return a == b


def _unknown_in(*values) -> bool:
    return any(v is UNKNOWN for v in values)


def _string(v) -> str:
    if isinstance(v, bool):
        return "true" if v else "false"
    if _is_num(v):
        return str(int(v)) if float(v).is_integer() else repr(v)
    if isinstance(v, str):
        return v
    raise EvalError(f"cannot convert {v!r} to string")


def _number(v):
    if _is_num(v):
        return v
    if isinstance(v, str):
        try:
            f = float(v)
        except ValueError:
            raise EvalError(f"cannot convert {v!r} to number") from None
        return int(f) if f.is_integer() else f
    raise EvalError(f"cannot convert {v!r} to number")


def _bool(v):
    if isinstance(v, bool):
        return v
    if v in ("true", "false"):
        return v == "true"
    raise EvalError(f"cannot convert {v!r} to bool")


def _collection(v) -> list:
    if isinstance(v, dict):
        return list(v.values())
    if isinstance(v, list):
        return v
    raise EvalError(f"{v!r} is not a collection")


def _flatten(v) -> list:
    out = []
    for x in v:
        out += _flatten(x) if isinstance(x, list) else [x]
    return out


def _format(fmt, *args):
    it = iter(args)

    def sub(m):
        return "%" if m.group(0) == "%%" else _string(next(it))

    return re.sub(r"%%|%[-+# 0]*\d*(?:\.\d+)?([a-zA-Z])", sub, fmt)


def _regex(pattern, s):
    m = re.search(pattern, s)
    if not m:
        raise EvalError("regex did not match")
    if m.groupdict():
        return m.groupdict()
    return list(m.groups()) if m.groups() else m.group(0)


def _lookup(m, k, *default):
    if k in m:
        return m[k]
    if default:
        return default[0]
    raise EvalError(f"lookup: no key {k!r}")


def _one(v):
    if len(v) > 1:
        raise EvalError("one: more than one element")
    return v[0] if v else None


def _coalesce(*args):
    for a in args:
        if a is not None and a != "":
            return a
    raise EvalError("coalesce: no non-null argument")


_FUNCTIONS = {
    "abs": abs,
    "alltrue": lambda v: all(_bool(x) for x in v),
    "anytrue": lambda v: any(_bool(x) for x in v),
    "can": None, "try": None,  # lazy; handled in _call
    "ceil": lambda v: math.ceil(v),
    "coalesce": _coalesce,
    "coalescelist": lambda *a: next((x for x in a if x), []),
    "compact": lambda v: [x for x in v if x not in (None, "")],
    "concat": lambda *a: [x for seq in a for x in seq],
    "contains": lambda c, v: any(_eq(x, v) for x in _collection(c)),
    "distinct": lambda v: [x for i, x in enumerate(v) if not any(_eq(x, y) for y in v[:i])],
    "element": lambda v, i: v[int(i) % len(v)],
    "endswith": lambda s, x: s.endswith(x),
    "flatten": _flatten,
    "floor": lambda v: math.floor(v),
    "format": _format,
    "join": lambda sep, *ls: sep.join(_string(x) for seq in ls for x in seq),
    "jsonencode": lambda v: json.dumps(v, separators=(",", ":")),
    "keys": lambda m: sorted(m),
    "length": len,
    "lookup": _lookup,
    "lower": lambda s: s.lower(),
    "max": lambda *a: max(_number(x) for x in a),
    "merge": lambda *a: {k: v for m in a if m is not None for k, v in m.items()},
    "min": lambda *a: min(_number(x) for x in a),
    "one": _one,
    "range": lambda *a: list(range(*[int(x) for x in a])),
    "regex": _regex,
    "replace": lambda s, a, b: s.replace(a, b),
    "split": lambda sep, s: s.split(sep),
    "startswith": lambda s, x: s.startswith(x),
    "substr": lambda s, o, n: s[int(o):] if n < 0 else s[int(o):int(o) + int(n)],
    "sum": lambda v: sum(_number(x) for x in v),
    "title": lambda s: s.title(),
    "tobool": _bool,
    "tolist": list,
    "tomap": dict,
    "tonumber": _number,
    "toset": lambda v: sorted(set(v), key=str) if all(isinstance(x, str) for x in v) else list(v),
    "tostring": _string,
    "trimprefix": lambda s, p: s[len(p):] if s.startswith(p) else s,
    "trimspace": lambda s: s.strip(),
    "trimsuffix": lambda s, p: s[: -len(p)] if p and s.endswith(p) else s,
    "upper": lambda s: s.upper(),
    "values": lambda m: [m[k] for k in sorted(m)],
    "zipmap": lambda k, v: dict(zip(k, v, strict=True)),
}


class Evaluator:
    """Evaluates expression trees for one assignment of input values."""

    def __init__(self, module: Module, inputs: dict):
        self.m = module
        self.inputs = inputs
        self._vars: dict = {}
        self._locals: dict = {}

    def var(self, name: str):
        if name not in self._vars:
            v = self.m.variables.get(name)
            if v is None:
                raise EvalError(f"undeclared variable {name!r}")
            if name in self.inputs:
                raw = self.inputs[name]
            elif v.has_default:
                raw = self.eval(v.default)
            else:
                raw = UNKNOWN
            self._vars[name] = convert(self, v.type, raw)
        return self._vars[name]

    def local(self, name: str):
        if name not in self._locals:
            if name not in self.m.locals:
                raise EvalError(f"undeclared local {name!r}")
            self._locals[name] = UNKNOWN  # cycle guard
            try:
                self._locals[name] = self.eval(self.m.locals[name])
            except EvalError as exc:
                self._locals[name] = exc
        value = self._locals[name]
        if isinstance(value, EvalError):
            raise value
        return value

    def eval(self, node: dict, env: dict | None = None):
        env = env or {}
        t = node["t"]
        if t == "lit":
            return node["v"]
        if t == "ref":
            return self._ref(node["steps"], env)
        if t == "rel":
            return self._traverse(self.eval(node["src"], env), node["steps"])
        if t == "index":
            return self._index(self.eval(node["coll"], env), self.eval(node["key"], env))
        if t == "template":
            parts = [self.eval(p, env) for p in node["parts"]]
            if _unknown_in(*parts):
                return UNKNOWN
            if any(p is None for p in parts):
                raise EvalError("null in template")
            return "".join(_string(p) for p in parts)
        if t == "binary":
            return self._binary(node, env)
        if t == "unary":
            x = self.eval(node["x"], env)
            if x is UNKNOWN:
                return UNKNOWN
            return (not _bool(x)) if node["op"] == "!" else -_number(x)
        if t == "cond":
            c = self.eval(node["if"], env)
            if c is UNKNOWN:
                a, b = self._try(node["then"], env), self._try(node["else"], env)
                return a if a is not UNKNOWN and b is not UNKNOWN and _eq(a, b) else UNKNOWN
            return self.eval(node["then"] if _bool(c) else node["else"], env)
        if t == "call":
            return self._call(node, env)
        if t == "tuple":
            return [self.eval(i, env) for i in node["items"]]
        if t == "object":
            out = {}
            for item in node["items"]:
                k = self.eval(item["k"], env)
                if k is UNKNOWN:
                    return UNKNOWN
                out[_string(k)] = self.eval(item["v"], env)
            return out
        if t == "for":
            return self._for(node, env)
        if t == "splat":
            src = self.eval(node["src"], env)
            if src is UNKNOWN:
                return UNKNOWN
            items = [] if src is None else src if isinstance(src, list) else [src]
            return [self.eval(node["each"], {**env, "__anon": x}) for x in items]
        if t == "anon":
            return env.get("__anon", UNKNOWN)
        return UNKNOWN

    def _try(self, node, env):
        try:
            return self.eval(node, env)
        except EvalError:
            return UNKNOWN

    def _ref(self, steps: list, env: dict):
        root = steps[0].get("attr")
        if root == "var" and len(steps) > 1:
            return self._traverse(self.var(steps[1]["attr"]), steps[2:])
        if root == "local" and len(steps) > 1:
            return self._traverse(self.local(steps[1]["attr"]), steps[2:])
        if root in env:
            return self._traverse(env[root], steps[1:])
        if root == "terraform" and len(steps) > 1 and steps[1].get("attr") == "workspace":
            return "default"
        return UNKNOWN  # resources, data sources, modules, path, self

    def _traverse(self, value, steps: list):
        for step in steps:
            if value is UNKNOWN:
                return UNKNOWN
            if "attr" in step:
                if not isinstance(value, dict) or step["attr"] not in value:
                    raise EvalError(f"no attribute {step['attr']!r}")
                value = value[step["attr"]]
            elif "index" in step:
                key = self.eval(step["index"])
                value = self._index(value, key)
            else:  # splat
                value = [] if value is None else value if isinstance(value, list) else [value]
        return value

    def _index(self, coll, key):
        if _unknown_in(coll, key):
            return UNKNOWN
        if isinstance(coll, dict):
            k = _string(key)
            if k not in coll:
                raise EvalError(f"no key {k!r}")
            return coll[k]
        if isinstance(coll, list):
            i = int(_number(key))
            if not 0 <= i < len(coll):
                raise EvalError(f"index {i} out of range")
            return coll[i]
        raise EvalError(f"cannot index {coll!r}")

    def _binary(self, node, env):
        op = node["op"]
        left = self.eval(node["l"], env)
        if op in ("&&", "||"):
            if left is not UNKNOWN and _bool(left) == (op == "||"):
                return left if op == "||" else False
            right = self.eval(node["r"], env)
            if right is not UNKNOWN and _bool(right) == (op == "||"):
                return right if op == "||" else False
            if _unknown_in(left, right):
                return UNKNOWN
            return _bool(right)
        right = self.eval(node["r"], env)
        if _unknown_in(left, right):
            return UNKNOWN
        if op == "==":
            return _eq(left, right)
        if op == "!=":
            return not _eq(left, right)
        a, b = _number(left), _number(right)
        if op == ">":
            return a > b
        if op == ">=":
            return a >= b
        if op == "<":
            return a < b
        if op == "<=":
            return a <= b
        if op == "+":
            return a + b
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        if op == "/":
            if b == 0:
                raise EvalError("division by zero")
            return a / b
        if op == "%":
            return a % b
        return UNKNOWN

    def _call(self, node, env):
        name = node["name"]
        if name == "try":
            for arg in node["args"]:
                try:
                    return self.eval(arg, env)
                except EvalError:
                    continue
            raise EvalError("try: every argument failed")
        if name == "can":
            try:
                return self.eval(node["args"][0], env) is not UNKNOWN or UNKNOWN
            except EvalError:
                return False
        fn = _FUNCTIONS.get(name)
        if fn is None:
            return UNKNOWN
        args = [self.eval(a, env) for a in node["args"]]
        if node.get("expand") and args:
            last = args.pop()
            if last is UNKNOWN:
                return UNKNOWN
            args += _collection(last)
        if any(_contains_unknown(a) for a in args):
            return UNKNOWN
        try:
            return fn(*args)
        except EvalError:
            raise
        except Exception as exc:
            raise EvalError(f"{name}: {exc}") from None

    def _for(self, node, env):
        coll = self.eval(node["coll"], env)
        if coll is UNKNOWN:
            return UNKNOWN
        if coll is None:
            raise EvalError("for over null")
        pairs = sorted(coll.items()) if isinstance(coll, dict) else list(enumerate(coll))
        as_object = "key" in node
        out: dict | list = {} if as_object else []
        for k, v in pairs:
            scope = {**env, node["vvar"]: v}
            if node["kvar"]:
                scope[node["kvar"]] = k
            if "cond" in node:
                c = self.eval(node["cond"], scope)
                if c is UNKNOWN:
                    return UNKNOWN
                if not _bool(c):
                    continue
            val = self.eval(node["val"], scope)
            if as_object:
                key = self.eval(node["key"], scope)
                if key is UNKNOWN:
                    return UNKNOWN
                key = _string(key)
                if node["group"]:
                    out.setdefault(key, []).append(val)
                else:
                    out[key] = val
            else:
                out.append(val)
        return out


def _contains_unknown(v) -> bool:
    if v is UNKNOWN:
        return True
    if isinstance(v, list):
        return any(_contains_unknown(x) for x in v)
    if isinstance(v, dict):
        return any(_contains_unknown(x) for x in v.values())
    return False


# ------------------------------------------------------------ type conversion

def _type_name(node) -> str | None:
    if node and node["t"] == "ref" and len(node["steps"]) == 1:
        return node["steps"][0]["attr"]
    return None


def convert(ev: Evaluator, type_node: dict | None, value):
    """An input value as OpenTofu would see it after type conversion,
    including optional() object attribute defaults."""
    if type_node is None or value is UNKNOWN or value is None:
        return value
    name = _type_name(type_node)
    if name == "string":
        return _string(value)
    if name == "number":
        return _number(value)
    if name == "bool":
        return _bool(value)
    if type_node["t"] != "call":
        return value
    fn, args = type_node["name"], type_node["args"]
    if fn in ("list", "set") and args:
        return [convert(ev, args[0], x) for x in _collection(value)]
    if fn == "map" and args and isinstance(value, dict):
        return {k: convert(ev, args[0], v) for k, v in value.items()}
    if fn == "tuple" and args and args[0]["t"] == "tuple":
        items = _collection(value)
        if len(items) != len(args[0]["items"]):
            raise EvalError("tuple length mismatch")
        return [convert(ev, t, x) for t, x in zip(args[0]["items"], items, strict=True)]
    if fn == "object" and args and args[0]["t"] == "object":
        if not isinstance(value, dict):
            raise EvalError(f"{value!r} is not an object")
        out = {}
        for item in args[0]["items"]:
            key = ev.eval(item["k"])
            attr_type, optional, default = item["v"], False, None
            if attr_type["t"] == "call" and attr_type["name"] == "optional":
                optional = True
                attr_type, rest = attr_type["args"][0], attr_type["args"][1:]
                default = ev.eval(rest[0]) if rest else None
            if key in value and value[key] is not None:
                out[key] = convert(ev, attr_type, value[key])
            elif optional:
                out[key] = convert(ev, attr_type, default)
            elif key in value:
                out[key] = None
            else:
                raise EvalError(f"missing object attribute {key!r}")
        return out
    return value


# ------------------------------------------------------------ resources

_META_BLOCKS = {"lifecycle", "provisioner", "connection", "precondition", "postcondition"}


def _instances(ev: Evaluator, res: Resource) -> list:
    """Instance scopes (count/each) of a resource; UNKNOWN expansion counts
    as one instance with unknown iterators."""
    attrs = res.body["attributes"]
    if "count" in attrs:
        n = ev.eval(attrs["count"]["expr"])
        if n is UNKNOWN:
            return [{"count": {"index": UNKNOWN}}]
        return [{"count": {"index": i}} for i in range(int(_number(n)))]
    if "for_each" in attrs:
        coll = ev.eval(attrs["for_each"]["expr"])
        if coll is UNKNOWN:
            return [{"each": {"key": UNKNOWN, "value": UNKNOWN}}]
        if isinstance(coll, dict):
            return [{"each": {"key": k, "value": v}} for k, v in coll.items()]
        return [{"each": {"key": v, "value": v}} for v in coll or []]
    return [{}]


def _values(ev: Evaluator, body: dict, env: dict) -> dict:
    """A block body's attribute values, nested blocks as lists of dicts, the
    shape plan JSON gives `values`."""
    out: dict = {}
    for name, attr in body["attributes"].items():
        if name in ("count", "for_each", "depends_on", "provider"):
            continue
        try:
            out[name] = ev.eval(attr["expr"], env)
        except EvalError:
            out[name] = UNKNOWN
    for blk in body["blocks"]:
        if blk["type"] in _META_BLOCKS:
            continue
        if blk["type"] == "dynamic" and blk["labels"]:
            label = blk["labels"][0]
            dyn = blk["body"]["attributes"]
            iterator = label
            if "iterator" in dyn and dyn["iterator"]["expr"]["t"] == "ref":
                iterator = dyn["iterator"]["expr"]["steps"][0]["attr"]
            content = next((b["body"] for b in blk["body"]["blocks"] if b["type"] == "content"), None)
            try:
                coll = ev.eval(dyn["for_each"]["expr"], env) if "for_each" in dyn else UNKNOWN
            except EvalError:
                coll = UNKNOWN
            if coll is UNKNOWN or content is None:
                out[label] = UNKNOWN
                continue
            pairs = coll.items() if isinstance(coll, dict) else enumerate(coll or [])
            out.setdefault(label, [])
            for k, v in pairs:
                out[label].append(_values(ev, content, {**env, iterator: {"key": k, "value": v}}))
            continue
        out.setdefault(blk["type"], []).append(_values(ev, blk["body"], env))
    return out


# ------------------------------------------------------------ goals and guards

@dataclass(frozen=True)
class Goal:
    """A resource of `type` planned, matching `where` (checks.py semantics)."""
    type: str
    where: str  # canonical JSON of the where spec, so goals hash

    @property
    def spec(self) -> dict:
        return {"type": self.type, "plans": ["sweep"], "quantifier": "any",
                **({"where": json.loads(self.where)} if self.where != "null" else {})}

    def __str__(self) -> str:
        return self.type + ("" if self.where == "null" else f" where {self.where}")


def goals(specs: list) -> list:
    """Goals named by `resource` checks that accept any plan of the sweep."""
    found: list = []

    def walk(spec):
        if isinstance(spec, list):
            for s in spec:
                walk(s)
            return
        if not isinstance(spec, dict) or len(spec) != 1:
            return
        (name, body), = spec.items()
        if name in ("all_of", "any_of"):
            walk(body)
        elif name == "resource":
            plans = body.get("plans", "defaults")
            plans = plans if isinstance(plans, list) else [plans]
            if ("sweep" in plans and body.get("quantifier", "all") == "any"
                    and body.get("exists", True) and not body.get("if_present")):
                g = Goal(body["type"], json.dumps(body.get("where"), sort_keys=True))
                if g not in found:
                    found.append(g)

    walk(specs)
    return found


def _goal_met(ev: Evaluator, goal: Goal) -> bool:
    where = json.loads(goal.where)
    for res in ev.m.resources:
        if res.mode != "resource" or res.type != goal.type:
            continue
        try:
            for env in _instances(ev, res):
                if where is None or checks._match_where(_values(ev, res.body, env), where):
                    return True
        except EvalError:
            continue
    return False


def _guards(ev: Evaluator) -> list:
    """(label, result) of every validation and precondition: True, False,
    UNKNOWN, or an EvalError."""
    out: list = []

    def check(label, node, env=None):
        try:
            out.append((label, ev.eval(node, env)))
        except EvalError as exc:
            out.append((label, exc))

    for name, v in ev.m.variables.items():
        for i, cond in enumerate(v.validations):
            check(f"var.{name} validation {i}", cond, {})
    for res in ev.m.resources:
        conds = _conditions(res.body, "precondition")
        if not conds:
            continue
        try:
            envs = _instances(ev, res)
        except EvalError as exc:
            out.append((f"{res.type}.{res.name} expansion", exc))
            continue
        for env in envs:
            for i, cond in enumerate(conds):
                check(f"{res.type}.{res.name} precondition {i}", cond, env)
    for i, cond in enumerate(ev.m.output_conditions):
        check(f"output precondition {i}", cond)
    return out


def _fails(result) -> bool:
    return isinstance(result, EvalError) or result is False


# ------------------------------------------------------------ input domains

def _input_path(m: Module, node: dict) -> tuple | None:
    """The input leaf an expression reads directly (var.x, var.x.attr), seen
    through locals that only alias one."""
    seen = set()
    while node["t"] == "ref":
        steps = node["steps"]
        root = steps[0].get("attr")
        if root == "var" and len(steps) > 1 and all("attr" in s for s in steps[1:]):
            return tuple(s["attr"] for s in steps[1:])
        if root == "local" and len(steps) == 2 and steps[1]["attr"] in m.locals:
            name = steps[1]["attr"]
            if name in seen:
                return None
            seen.add(name)
            node = m.locals[name]
            continue
        return None
    return None


def _literals(m: Module, node: dict) -> list | None:
    """The literal values of a tuple/object literal (or a local holding one)."""
    if node["t"] == "ref":
        steps = node["steps"]
        if steps[0].get("attr") == "local" and len(steps) == 2 and steps[1]["attr"] in m.locals:
            node = m.locals[steps[1]["attr"]]
    if node["t"] == "tuple":
        items = [i["v"] for i in node["items"] if i["t"] == "lit"]
        return items if len(items) == len(node["items"]) else None
    if node["t"] == "object":
        return [i["k"]["v"] for i in node["items"] if i["k"]["t"] == "lit"]
    if node["t"] == "lit" and isinstance(node["v"], (list, dict)):
        return list(node["v"])
    return None


def _walk(node):
    if isinstance(node, dict):
        if "t" in node:
            yield node
        for v in node.values():
            yield from _walk(v)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v)


def _module_exprs(m: Module):
    for v in m.variables.values():
        yield from v.validations
    yield from m.locals.values()
    for res in m.resources:
        yield res.body
    yield from m.output_conditions


_COMPARE = {"==", "!=", "<", "<=", ">", ">="}


def constants(m: Module) -> dict:
    """input path -> values the module itself compares that input against:
    comparison operands (and their neighbours for ordering), contains()
    lists, and the keys of maps the input indexes."""
    found: dict = {}

    def add(path, values):
        if path is None:
            return
        bucket = found.setdefault(path, [])
        for v in values:
            if not any(_eq(v, x) for x in bucket):
                bucket.append(v)

    for root in _module_exprs(m):
        for n in _walk(root):
            if n["t"] == "binary" and n["op"] in _COMPARE:
                for a, b in ((n["l"], n["r"]), (n["r"], n["l"])):
                    if b["t"] == "lit":
                        c = b["v"]
                        near = [c - 1, c, c + 1] if _is_num(c) and n["op"] not in ("==", "!=") else [c]
                        add(_input_path(m, a), near)
            elif n["t"] == "call" and n["name"] == "contains" and len(n["args"]) == 2:
                values = _literals(m, n["args"][0])
                if values:
                    add(_input_path(m, n["args"][1]), values)
            elif n["t"] == "call" and n["name"] == "lookup" and len(n["args"]) >= 2:
                values = _literals(m, n["args"][0])
                if values:
                    add(_input_path(m, n["args"][1]), values)
            elif n["t"] == "index":
                values = _literals(m, n["coll"])
                if values:
                    add(_input_path(m, n["key"]), values)
    return found


def _leaf_type(m: Module, path: tuple) -> dict | None:
    v = m.variables.get(path[0])
    node = v.type if v else None
    for key in path[1:]:
        if not node or node["t"] != "call" or node["name"] != "object" or not node["args"]:
            return None
        node = next((i["v"] for i in node["args"][0]["items"]
                     if i["k"]["t"] == "lit" and i["k"]["v"] == key), None)
        if node and node["t"] == "call" and node["name"] == "optional":
            node = node["args"][0]
    return node


def _get(value, path: tuple):
    for key in path:
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def _set(value, path: tuple, leaf):
    if not path:
        return leaf
    value = dict(value) if isinstance(value, dict) else {}
    value[path[0]] = _set(value.get(path[0]), path[1:], leaf)
    return value


def _sample_values(m: Module, samples: dict) -> dict:
    """input path -> fixture sample values for the resource attributes
    (`type.attr`) that input feeds directly. Samples carry what the source
    cannot: a value the provider accepts, such as a well-formed resource ID."""
    found: dict = {}
    for res in m.resources:
        for name, attr in res.body["attributes"].items():
            key = f"{res.type}.{name}"
            if key in samples:
                path = _input_path(m, attr["expr"])
                if path is not None:
                    found.setdefault(path, []).append(samples[key])
    return found


def domains(m: Module, base: dict, samples: dict | None = None) -> dict:
    """input path -> candidate values other than the current one."""
    out: dict = {}
    consts = constants(m)
    for path, values in _sample_values(m, samples or {}).items():
        consts.setdefault(path, []).extend(values)
    paths = set(consts)
    for name, v in m.variables.items():
        if _type_name(v.type) == "bool":
            paths.add((name,))
    for path in paths:
        if path[0] not in m.variables:
            continue
        current = _get(base.get(path[0]), path[1:]) if len(path) > 1 else base.get(path[0])
        candidates = list(consts.get(path, []))
        if _type_name(_leaf_type(m, path)) == "bool":
            candidates += [True, False]
        candidates = [c for i, c in enumerate(candidates)
                      if not any(_eq(c, x) for x in candidates[:i]) and not _eq(c, current)]
        if _is_num(current):  # nearest values first: the smallest change that works
            candidates.sort(key=lambda c: abs(c - current) if _is_num(c) else math.inf)
        if candidates:
            out[path] = candidates
    return out


def _deps(m: Module, roots: list) -> set:
    """Variable names a set of expressions reads, through locals."""
    names: set = set()
    seen: set = set()
    stack = list(roots)
    while stack:
        for n in _walk(stack.pop()):
            if n["t"] != "ref":
                continue
            steps = n["steps"]
            root = steps[0].get("attr")
            if root == "var" and len(steps) > 1:
                names.add(steps[1]["attr"])
            elif root == "local" and len(steps) > 1 and steps[1].get("attr") not in seen:
                seen.add(steps[1]["attr"])
                if steps[1]["attr"] in m.locals:
                    stack.append(m.locals[steps[1]["attr"]])
    return names


# ------------------------------------------------------------ search

@dataclass
class Witness:
    goal: Goal
    inputs: dict          # every variable's input value
    changed: dict         # dotted input path -> value

    def plan_inputs(self, defaults_inputs: dict) -> dict:
        """The defaults plan's inputs plus the changed variables."""
        names = {path.split(".")[0] for path in self.changed}
        return {**defaults_inputs, **{n: self.inputs[n] for n in sorted(names)}}


def solve(m: Module, goal: Goal, base: dict, samples: dict | None = None) -> list:
    """Assignments, fewest changed input leaves first, under which `goal` is
    met and no validation or precondition fails. Guards that already fail at
    `base` (which planned successfully) are evaluator blind spots and are
    ignored."""
    baseline = {label for label, r in _guards(Evaluator(m, base)) if _fails(r)}
    roots = [r.body for r in m.resources if r.mode == "resource" and r.type == goal.type]
    relevant = _deps(m, roots)
    guard_exprs = [c for v in m.variables.values() for c in v.validations]
    guard_exprs += [c for r in m.resources for c in _conditions(r.body, "precondition")]
    for cond in guard_exprs:  # inputs that guard the goal's inputs
        names = _deps(m, [cond])
        if names & relevant:
            relevant |= names
    dom = {p: c for p, c in domains(m, base, samples).items() if p[0] in relevant}
    leaves = sorted(dom)

    witnesses: list = []
    evaluations = 0
    for k in range(0, min(MAX_CHANGED, len(leaves)) + 1):
        for combo in itertools.combinations(leaves, k):
            for values in itertools.product(*(dom[p] for p in combo)):
                evaluations += 1
                if evaluations > MAX_EVALUATIONS:
                    return witnesses
                inputs = copy.deepcopy(base)
                for path, value in zip(combo, values, strict=True):
                    inputs[path[0]] = _set(inputs.get(path[0]), path[1:], value)
                ev = Evaluator(m, inputs)
                try:
                    if not _goal_met(ev, goal):
                        continue
                except EvalError:
                    continue
                if any(_fails(r) and label not in baseline for label, r in _guards(ev)):
                    continue
                witnesses.append(Witness(goal, inputs, {".".join(p): v for p, v in zip(combo, values, strict=True)}))
                if len(witnesses) >= MAX_WITNESSES:
                    return witnesses
    return witnesses


def base_inputs(m: Module, defaults_inputs: dict) -> dict:
    """Every variable's input value at defaults: the required inputs given,
    the declared defaults for the rest."""
    ev = Evaluator(m, {})
    out = dict(defaults_inputs)
    for name, v in m.variables.items():
        if name not in out and v.has_default:
            try:
                value = ev.eval(v.default)
            except EvalError:
                continue
            if value is not UNKNOWN:
                out[name] = value
    return out


# ------------------------------------------------------------ value proofs

# A closed value set larger than this is treated as open.
MAX_POSSIBLE = 64


def _union(sets: list) -> list | None:
    out: list = []
    for s in sets:
        if s is None:
            return None
        for v in s:
            if not any(_eq(v, x) for x in out):
                out.append(v)
    return out if len(out) <= MAX_POSSIBLE else None


def _allowed(m: Module, cond: dict, path: tuple) -> list | None:
    """Values a validation condition admits for input `path`, when the
    condition confines it to a literal set: `contains([...], x)`, `x == lit`,
    their disjunction, or a conjunction with one confining side."""
    t = cond["t"]
    if t == "call" and cond["name"] == "contains" and len(cond["args"]) == 2:
        if _input_path(m, cond["args"][1]) == path:
            return _literals(m, cond["args"][0])
        return None
    if t == "binary" and cond["op"] == "==":
        for a, b in ((cond["l"], cond["r"]), (cond["r"], cond["l"])):
            if b["t"] == "lit" and _input_path(m, a) == path:
                return [b["v"]]
        return None
    if t == "binary" and cond["op"] == "||":
        return _union([_allowed(m, cond["l"], path), _allowed(m, cond["r"], path)])
    if t == "binary" and cond["op"] == "&&":
        left, right = _allowed(m, cond["l"], path), _allowed(m, cond["r"], path)
        if left is not None and right is not None:
            return [v for v in left if any(_eq(v, x) for x in right)]
        return left if left is not None else right
    return None


def _input_domain(m: Module, path: tuple) -> list | None:
    """Every value input `path` can take: both values of a bool, or the
    literal set a validation confines it to. Otherwise open (None)."""
    v = m.variables.get(path[0])
    if v is None:
        return None
    for cond in v.validations:
        allowed = _allowed(m, cond, path)
        if allowed is not None:
            return allowed
    if _type_name(_leaf_type(m, path)) == "bool":
        return [True, False]
    return None


def possible_values(m: Module, node: dict, seen: frozenset = frozenset()) -> list | None:
    """Every value an expression can produce under any accepted inputs, or
    None when that set is open or unknown. Conditionals contribute both
    branches whatever their condition, so the set may be larger than what is
    reachable, never smaller: when every member is secure, every reachable
    value is."""
    t = node["t"]
    if t == "lit":
        return [node["v"]]
    if t == "cond":
        return _union([possible_values(m, node["then"], seen), possible_values(m, node["else"], seen)])
    if t == "ref":
        steps = node["steps"]
        root = steps[0].get("attr")
        if root == "local" and len(steps) == 2 and steps[1]["attr"] in m.locals:
            name = steps[1]["attr"]
            if name in seen:
                return None
            return possible_values(m, m.locals[name], seen | {name})
        path = _input_path(m, node)
        return _input_domain(m, path) if path else None
    if t == "index":
        return _map_values(m, node["coll"], seen)
    if t == "call" and node["name"] == "lookup" and len(node["args"]) >= 2:
        sets = [_map_values(m, node["args"][0], seen)]
        sets += [possible_values(m, a, seen) for a in node["args"][2:]]
        return _union(sets)
    if t == "call" and node["name"] in ("coalesce", "try") and not node.get("expand"):
        return _union([possible_values(m, a, seen) for a in node["args"]])
    return None


def _map_values(m: Module, coll: dict, seen: frozenset) -> list | None:
    """The values of a map or list literal (directly or through a local),
    whichever key selects them."""
    if coll["t"] == "ref":
        steps = coll["steps"]
        if steps[0].get("attr") == "local" and len(steps) == 2 and steps[1]["attr"] in m.locals:
            name = steps[1]["attr"]
            if name in seen:
                return None
            return _map_values(m, m.locals[name], seen | {name})
        return None
    if coll["t"] == "object":
        return _union([possible_values(m, i["v"], seen) for i in coll["items"]])
    if coll["t"] == "tuple":
        return _union([possible_values(m, i, seen) for i in coll["items"]])
    if coll["t"] == "lit" and isinstance(coll["v"], (dict, list)):
        vals = coll["v"].values() if isinstance(coll["v"], dict) else coll["v"]
        return _union([[v] for v in vals])
    return None


_MISSING_ATTR = object()


def attr_nodes(body: dict, path: list) -> list:
    """Expression trees at a dotted attribute path through nested blocks.
    A missing attribute yields _MISSING_ATTR; a `dynamic` block on the path
    yields None (generated content is never closed)."""
    head, rest = path[0], path[1:]
    if not rest:
        attr = body["attributes"].get(head)
        return [attr["expr"] if attr else _MISSING_ATTR]
    if any(b["type"] == "dynamic" and b["labels"][:1] == [head] for b in body["blocks"]):
        return [None]
    blocks = [b for b in body["blocks"] if b["type"] == head]
    if not blocks:
        return [_MISSING_ATTR]
    return [n for b in blocks for n in attr_nodes(b["body"], rest)]


def existence_open(m: Module, res: Resource) -> bool:
    """True when any input (through locals) gates the resource's existence."""
    attrs = res.body["attributes"]
    return any(_deps(m, [attrs[k]["expr"]]) for k in ("count", "for_each") if k in attrs)
