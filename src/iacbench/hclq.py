"""Static HCL queries over a module directory (python-hcl2 based).

Used by generation scoring for interface stats and variable-taint checks.
Parsing is best-effort: files that fail to parse are skipped (the functional
gate already proved tofu accepts them).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import hcl2

_VAR_REF = re.compile(r"\bvar\.([A-Za-z0-9_-]+)")
_LOCAL_REF = re.compile(r"\blocal\.([A-Za-z0-9_-]+)")


def _unquote(value):
    if isinstance(value, str) and len(value) >= 2 and value[0] == '"' and value[-1] == '"':
        return value[1:-1]
    return value


def _clean(value):
    """Normalize python-hcl2 8.x output: strip __is_block__ markers and the
    literal quote characters it keeps on block labels and string values."""
    if isinstance(value, dict):
        # __is_block__, __comments__, and any future parser metadata
        return {_unquote(k): _clean(v) for k, v in value.items() if not k.startswith("__")}
    if isinstance(value, list):
        return [_clean(v) for v in value]
    return _unquote(value)


def parse_dir(module_dir: Path) -> list:
    docs = []
    for tf in sorted(Path(module_dir).glob("*.tf")):
        try:
            with open(tf) as f:
                docs.append(_clean(hcl2.load(f)))
        except Exception:
            continue
    return docs


def variables(module_dir: Path) -> dict:
    """name -> {typed: bool, has_default: bool, has_validation: bool}"""
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("variable", []) or []:
            for name, spec in block.items():
                spec = spec or {}
                out[name] = {
                    "typed": "type" in spec,
                    "has_default": "default" in spec,
                    "has_validation": bool(spec.get("validation")),
                }
    return out


def locals_map(module_dir: Path) -> dict:
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("locals", []) or []:
            out.update(block or {})
    return out


def _refs(value) -> tuple:
    text = json.dumps(value, default=str)
    return set(_VAR_REF.findall(text)), set(_LOCAL_REF.findall(text))


def tainted_locals(module_dir: Path) -> set:
    """Locals whose value derives (transitively) from any variable."""
    loc = locals_map(module_dir)
    tainted: set = set()
    changed = True
    while changed:
        changed = False
        for name, value in loc.items():
            if name in tainted:
                continue
            var_refs, local_refs = _refs(value)
            if var_refs or (local_refs & tainted):
                tainted.add(name)
                changed = True
    return tainted


def resource_attrs(module_dir: Path, resource_type: str) -> list:
    """All attribute dicts of resources of the given type."""
    found = []
    for doc in parse_dir(module_dir):
        for block in doc.get("resource", []) or []:
            for rtype, instances in block.items():
                if rtype == resource_type:
                    for _name, attrs in instances.items():
                        found.append(attrs or {})
    return found


def attrs_var_tainted(module_dir: Path, resource_type: str, attr_names: list) -> bool:
    """True if any listed attribute of any resource of this type derives from a variable."""
    tainted = tainted_locals(module_dir)
    for attrs in resource_attrs(module_dir, resource_type):
        for attr in attr_names:
            if attr not in attrs:
                continue
            var_refs, local_refs = _refs(attrs[attr])
            if var_refs or (local_refs & tainted):
                return True
    return False


def _var_closure(loc: dict, value) -> set:
    """All variables reaching a value, transitively through locals."""
    var_refs, local_refs = _refs(value)
    seen: set = set()
    stack = list(local_refs)
    while stack:
        name = stack.pop()
        if name in seen or name not in loc:
            continue
        seen.add(name)
        more_vars, more_locals = _refs(loc[name])
        var_refs |= more_vars
        stack.extend(more_locals - seen)
    return var_refs


def vars_feeding_attr(module_dir: Path, attr_name: str) -> set:
    """Variables that (transitively) feed any resource attribute with this name."""
    loc = locals_map(module_dir)
    out: set = set()
    for doc in parse_dir(module_dir):
        for block in doc.get("resource", []) or []:
            for _rtype, instances in block.items():
                for _name, attrs in instances.items():
                    if attr_name in (attrs or {}):
                        out |= _var_closure(loc, attrs[attr_name])
    return out


def vars_feeding_attrs_except(module_dir: Path, excluded_attr: str) -> set:
    """Variables that feed any resource attribute OTHER than the excluded one."""
    loc = locals_map(module_dir)
    out: set = set()
    for doc in parse_dir(module_dir):
        for block in doc.get("resource", []) or []:
            for _rtype, instances in block.items():
                for _name, attrs in instances.items():
                    for attr, value in (attrs or {}).items():
                        if attr != excluded_attr:
                            out |= _var_closure(loc, value)
    return out


def value_text_closure(module_dir: Path, value) -> str:
    """The textual expansion of a value plus every local it (transitively)
    references — lets checks see through `local.x` indirection."""
    loc = locals_map(module_dir)
    seen: set = set()
    parts: list = []

    def add(v) -> None:
        text = json.dumps(v, default=str)
        parts.append(text)
        for name in _LOCAL_REF.findall(text):
            if name not in seen and name in loc:
                seen.add(name)
                add(loc[name])

    add(value)
    return " ".join(parts)


def outputs(module_dir: Path) -> dict:
    """name -> raw value text of output blocks in the module root."""
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("output", []) or []:
            for name, spec in block.items():
                out[name] = json.dumps(spec, default=str)
    return out


def _line_counts(module_dir: Path) -> tuple:
    """(sloc, comment_lines) across *.tf files, excluding .terraform and README."""
    sloc = comments = 0
    for tf in sorted(Path(module_dir).rglob("*.tf")):
        if ".terraform" in tf.parts:
            continue
        for line in tf.read_text(errors="replace").splitlines():
            stripped = line.strip()
            if not stripped:
                continue
            if stripped.startswith("#") or stripped.startswith("//"):
                comments += 1
            else:
                sloc += 1
    return sloc, comments


def stats(module_dir: Path) -> dict:
    """Descriptive interface stats — recorded, never weighted (SLOC caveat applies)."""
    v = variables(module_dir)
    n = len(v)
    resource_count = 0
    for doc in parse_dir(module_dir):
        for block in doc.get("resource", []) or []:
            for _rtype, instances in block.items():
                resource_count += len(instances)
    sloc, comment_lines = _line_counts(module_dir)
    return {
        "variable_count": n,
        "typed_pct": round(sum(1 for s in v.values() if s["typed"]) / n, 2) if n else None,
        "validated_pct": round(sum(1 for s in v.values() if s["has_validation"]) / n, 2) if n else None,
        "locals_count": len(locals_map(module_dir)),
        "resource_count": resource_count,
        "tf_sloc": sloc,
        "tf_comment_lines": comment_lines,
        "comment_ratio": round(comment_lines / sloc, 3) if sloc else None,
    }
