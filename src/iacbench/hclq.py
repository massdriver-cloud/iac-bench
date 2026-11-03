"""Static HCL queries over a module directory, parsed by HashiCorp's HCL
library through tools/hclast (see hclast.py).

Used by generation scoring for interface stats and variable-taint checks.
Parsing is best-effort: files that fail to parse are skipped (the functional
gate already proved tofu accepts them).
"""

from __future__ import annotations

import json
import re
from pathlib import Path

from . import hclast

_VAR_REF = re.compile(r"\bvar\.([A-Za-z0-9_-]+)")
_LOCAL_REF = re.compile(r"\blocal\.([A-Za-z0-9_-]+)")
_DATA_REF = re.compile(r"\bdata\.([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)")
_EACH_REF = re.compile(r"\beach\.(key|value)\b")


def parse_dir(module_dir: Path) -> list:
    return hclast.parse_dir(Path(module_dir))


def variables(module_dir: Path) -> dict:
    """name -> {typed, has_default, has_validation, default, type, validation_conditions}

    `default` is the parsed default value (None either means "no default" or a
    literal null — disambiguate with has_default). `validation_conditions` are
    the raw condition expression texts, used by the perturbation sweep to
    harvest allowed values."""
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("variable", []) or []:
            for name, spec in block.items():
                spec = spec or {}
                validations = spec.get("validation") or []
                if isinstance(validations, dict):
                    validations = [validations]
                out[name] = {
                    "typed": "type" in spec,
                    "has_default": "default" in spec,
                    "has_description": bool(str(spec.get("description") or "").strip()),
                    "has_validation": bool(validations),
                    "default": spec.get("default"),
                    "type": str(spec.get("type", "")),
                    "validation_conditions": [
                        str((v or {}).get("condition", "")) for v in validations
                    ],
                }
    return out


_CONTAINS_RE = re.compile(r"contains\(\s*\[([^\]]*)\]")


def allowed_values(meta: dict) -> list:
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


def parse_tfvars(path: Path) -> dict:
    """Parse a .tfvars (HCL) or .tfvars.json file into a plain dict. tfvars
    values are literals by definition; expressions surface as ${...} strings
    and are the author's contract violation, not ours to resolve."""
    path = Path(path)
    if path.suffix == ".json":
        return json.loads(path.read_text())
    return hclast.parse_file(path) or {}


def locals_map(module_dir: Path) -> dict:
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("locals", []) or []:
            out.update(block or {})
    return out


def data_map(module_dir: Path) -> dict:
    """(data source type, name) -> its argument block."""
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("data", []) or []:
            for dtype, instances in (block or {}).items():
                for name, attrs in (instances or {}).items():
                    out[(dtype, name)] = attrs or {}
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


def _var_closure(loc: dict, value, data: dict | None = None) -> set:
    """All variables reaching a value, transitively through locals. With a
    `data` map (see data_map), also through the arguments of any data source
    the value reads — a lookup keyed by a variable carries that variable."""
    var_refs: set = set()
    seen: set = set()
    stack = [value]
    while stack:
        v = stack.pop()
        more_vars, more_locals = _refs(v)
        var_refs |= more_vars
        for name in more_locals:
            if ("local", name) not in seen and name in loc:
                seen.add(("local", name))
                stack.append(loc[name])
        if data is not None:
            for ref in _DATA_REF.findall(json.dumps(v, default=str)):
                if ("data", ref) not in seen and ref in data:
                    seen.add(("data", ref))
                    stack.append(data[ref])
    return var_refs


def _attr_values(node, attr_name: str):
    """Every value assigned to `attr_name` at any depth: top-level attributes,
    nested blocks (parsed as lists of dicts), and `dynamic` block content."""
    if isinstance(node, dict):
        for key, value in node.items():
            if key == attr_name:
                yield value
            yield from _attr_values(value, attr_name)
    elif isinstance(node, list):
        for item in node:
            yield from _attr_values(item, attr_name)


def _strip_indexes(text: str) -> str:
    """Drop bracketed index expressions: `x[each.key]` selects an instance of
    something else, it does not pass the for_each value through."""
    prev = None
    while prev != text:
        prev, text = text, re.sub(r"\[[^\[\]]*\]", "", text)
    return text


def vars_feeding_attr(
    module_dir: Path, attr_name: str, rtype: str | None = None, through_data: bool = False
) -> set:
    """Variables that (transitively) feed any resource attribute with this
    name, including attributes inside nested and dynamic blocks. `rtype`
    restricts the search to one resource type; `through_data` also follows
    data-source lookups keyed by a variable. A value built from `each.key`
    or `each.value` carries the variables feeding the resource's for_each,
    unless it only uses them as an index into something else."""
    loc = locals_map(module_dir)
    data = data_map(module_dir) if through_data else None
    out: set = set()
    for doc in parse_dir(module_dir):
        for block in doc.get("resource", []) or []:
            for found_type, instances in block.items():
                if rtype is not None and found_type != rtype:
                    continue
                for _name, attrs in instances.items():
                    attrs = attrs or {}
                    each_vars = _var_closure(loc, attrs["for_each"], data) if "for_each" in attrs else set()
                    for value in _attr_values(attrs, attr_name):
                        out |= _var_closure(loc, value, data)
                        if each_vars and _EACH_REF.search(_strip_indexes(json.dumps(value, default=str))):
                            out |= each_vars
    return out


def vars_feeding_provider_attr(module_dir: Path, attr_name: str, provider: str | None = None) -> set:
    """Variables that (transitively) feed a provider configuration attribute
    with this name, including attributes inside nested blocks such as
    default_tags. `provider` restricts the search to one provider."""
    loc = locals_map(module_dir)
    out: set = set()
    for name, attrs in provider_blocks(module_dir):
        if provider is not None and name != provider:
            continue
        for value in _attr_values(attrs, attr_name):
            out |= _var_closure(loc, value)
    return out


def value_text_closure(module_dir: Path, value) -> str:
    """The textual expansion of a value plus every local and data source it
    (transitively) references — lets checks see through `local.x` and
    `data.aws_iam_policy_document.x.json`-style indirection."""
    loc = locals_map(module_dir)
    data = data_map(module_dir)
    seen: set = set()
    parts: list = []

    def add(v) -> None:
        text = json.dumps(v, default=str)
        parts.append(text)
        for name in _LOCAL_REF.findall(text):
            if ("local", name) not in seen and name in loc:
                seen.add(("local", name))
                add(loc[name])
        for ref in _DATA_REF.findall(text):
            if ("data", ref) not in seen and ref in data:
                seen.add(("data", ref))
                add(data[ref])

    add(value)
    return " ".join(parts)


def required_providers(module_dir: Path) -> dict:
    """provider name -> version constraint string (or None) from
    terraform.required_providers blocks anywhere under the module
    (local submodules included — an unbounded provider is no less
    unbounded for living in a subdirectory)."""
    out: dict = {}
    for doc in _parse_all(module_dir):
        for block in doc.get("terraform", []) or []:
            rp = (block or {}).get("required_providers")
            if not rp:
                continue
            for entry in rp if isinstance(rp, list) else [rp]:
                for name, spec in (entry or {}).items():
                    out[name] = spec.get("version") if isinstance(spec, dict) else spec
    return out


def _module_dirs(module_dir: Path) -> list:
    """The module root and every local submodule directory under it."""
    dirs = {tf.parent for tf in Path(module_dir).rglob("*.tf") if ".terraform" not in tf.parts}
    return sorted(dirs)


def _parse_all(module_dir: Path) -> list:
    """Parse every *.tf under the module dir (excluding .terraform)."""
    return [doc for d in _module_dirs(module_dir) for doc in hclast.parse_dir(d)]


def provider_blocks(module_dir: Path) -> list:
    """(provider_name, attrs) for every provider configuration block."""
    out: list = []
    for doc in parse_dir(module_dir):
        for block in doc.get("provider", []) or []:
            for name, attrs in block.items():
                out.append((name, attrs or {}))
    return out


def value_text(value) -> str:
    """Textual form of a parsed HCL value (no locals resolution)."""
    return json.dumps(value, default=str)


def outputs(module_dir: Path) -> dict:
    """name -> parsed output spec dict ({value, description, ...})."""
    out: dict = {}
    for doc in parse_dir(module_dir):
        for block in doc.get("output", []) or []:
            for name, spec in block.items():
                out[name] = spec or {}
    return out


def module_sources(module_dir: Path) -> list:
    """Source strings of every `module` block anywhere under the module dir
    (excluding .terraform) — used to enforce the no-remote-modules contract."""
    sources: list = []
    for doc in _parse_all(module_dir):
        for block in doc.get("module", []) or []:
            for _name, attrs in block.items():
                source = (attrs or {}).get("source")
                if source is not None:
                    sources.append(str(source))
    return sources


def unparsed_files(module_dir: Path) -> list:
    """*.tf files in the module root that the HCL parser rejects. Static
    checks are blind to these — callers must surface them, never hide them."""
    return hclast.unparsed_files(Path(module_dir))


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
