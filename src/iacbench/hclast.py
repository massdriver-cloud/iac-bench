"""OpenTofu configuration parsed by HashiCorp's HCL library.

`tools/hclast` (Go, hashicorp/hcl/v2) prints every attribute's source text,
literal value and references. `parse_dir` reshapes that into the document
shape the static lens consumes: one dict per file, blocks nested by label,
literals as values, other expressions as `${...}` text.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from functools import lru_cache
from pathlib import Path

from .paths import REPO_ROOT

_BINARY = Path(os.environ.get("IACBENCH_HCLAST", REPO_ROOT / "tools" / "hclast" / "hclast"))
_IDENT = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*$")


class HclastUnavailable(RuntimeError):
    pass


_SOURCES = [REPO_ROOT / "tools" / "hclast" / n for n in ("main.go", "go.mod", "go.sum")]


def _check_binary() -> None:
    """The binary must exist and, unless IACBENCH_HCLAST names one, have been
    built from the current source: `make` records the source's sha256 beside
    it, so a branch switch that rewrites identical files is not a rebuild."""
    if not _BINARY.is_file():
        raise HclastUnavailable(f"{_BINARY} not found; build it with `make -C tools/hclast`")
    if "IACBENCH_HCLAST" in os.environ:
        return
    stamp = _BINARY.with_name(_BINARY.name + ".sha256")
    source = hashlib.sha256(b"".join(s.read_bytes() for s in _SOURCES)).hexdigest()
    if not stamp.is_file() or stamp.read_text().strip() != source:
        raise HclastUnavailable(f"{_BINARY} was not built from the current source; rebuild it with `make -C tools/hclast`")


def _run(module_dir: Path) -> dict:
    _check_binary()
    out = subprocess.run([str(_BINARY), str(module_dir)], capture_output=True, text=True, check=True)
    return json.loads(out.stdout)["files"]


@lru_cache(maxsize=512)
def _files(module_dir: str, stamp: tuple) -> dict:
    return _run(Path(module_dir))


def _stamp(path: Path) -> tuple:
    if path.is_file():
        return ((path.name, path.stat().st_mtime_ns),)
    return tuple(sorted((p.name, p.stat().st_mtime_ns) for p in path.glob("*.tf")))


def files(path: Path) -> dict:
    """file name -> {"body": ...} or {"error": ...}, for a module directory's
    *.tf files or for one .tf/.tfvars file.

    For a directory, every local module it calls (`source = "./..."` inside the
    directory) joins it: the child's resources, data sources and locals appear
    as files named `<call>/<file>`, with each `var.<name>` replaced by the
    call's argument (or the child variable's default), and the child's locals,
    resources and data sources renamed `__<call>__<name>`. The child's
    variables, outputs, providers, terraform settings and module calls stay
    out, so the root's interface is unchanged. Static checks therefore see
    every resource the module deploys, wherever it is declared."""
    path = Path(path).resolve()
    if path.is_file():
        return _files(str(path), _stamp(path))
    return _flattened(str(path), _tree_stamp(path))


def _tree_stamp(path: Path) -> tuple:
    return tuple(sorted((str(p.relative_to(path)), p.stat().st_mtime_ns)
                        for p in path.rglob("*.tf") if ".terraform" not in p.parts))


@lru_cache(maxsize=512)
def _flattened(module_dir: str, stamp: tuple) -> dict:
    root = Path(module_dir)
    return _with_children(root, root, _files(module_dir, _stamp(root)), depth=0)


_CHILD_BLOCKS = ("resource", "data", "locals")
_MAX_DEPTH = 4


def _with_children(top: Path, here: Path, docs: dict, depth: int) -> dict:
    out = dict(docs)
    if depth >= _MAX_DEPTH:
        return out
    for _, f in sorted(docs.items()):
        for blk in (f.get("body") or {}).get("blocks", []):
            if blk["type"] != "module" or not blk.get("labels"):
                continue
            src = blk["body"]["attributes"].get("source", {}).get("literal")
            if not isinstance(src, str) or not src.startswith(("./", "../")):
                continue
            child = (here / src).resolve()
            if not child.is_dir() or not child.is_relative_to(top) or child == here:
                continue
            call = blk["labels"][0]
            child_docs = _with_children(top, child, _files(str(child), _stamp(child)), depth + 1)
            for name, body in _inline(call, blk["body"], child_docs).items():
                out[f"{call}/{name}"] = body
    return out


def _ident(call: str) -> str:
    return "__" + re.sub(r"[^A-Za-z0-9_]", "_", call) + "__"


def _inline(call: str, call_body: dict, child_docs: dict) -> dict:
    """The child's resource, data and locals blocks, rewritten into the
    caller's namespace."""
    import copy

    prefix = _ident(call)
    args = {k: v for k, v in call_body["attributes"].items()
            if k not in ("source", "version", "providers", "count", "for_each", "depends_on")}
    defaults, local_names, resources, datas = {}, set(), set(), set()
    for f in child_docs.values():
        for blk in (f.get("body") or {}).get("blocks", []):
            labels, attrs = blk.get("labels") or [], blk["body"]["attributes"]
            if blk["type"] == "variable" and labels and "default" in attrs:
                defaults[labels[0]] = attrs["default"]
            elif blk["type"] == "locals":
                local_names.update(attrs)
            elif blk["type"] == "resource" and len(labels) == 2:
                resources.add((labels[0], labels[1]))
            elif blk["type"] == "data" and len(labels) == 2:
                datas.add((labels[0], labels[1]))
    gate = {k: call_body["attributes"][k] for k in ("count", "for_each") if k in call_body["attributes"]}
    rw = _Rewriter(prefix, {**defaults, **args}, local_names, resources, datas)
    out = {}
    for name, f in child_docs.items():
        if "body" not in f:
            continue
        blocks = []
        for blk in f["body"].get("blocks", []):
            if blk["type"] not in _CHILD_BLOCKS:
                continue
            blk = copy.deepcopy(blk)
            labels = blk.get("labels") or []
            if blk["type"] == "locals":
                blk["body"]["attributes"] = {prefix + k: v for k, v in blk["body"]["attributes"].items()}
            rw.body(blk["body"])
            if blk["type"] in ("resource", "data") and len(labels) == 2:
                blk["labels"] = [labels[0], prefix + labels[1]]
                # The call's count/for_each (caller's namespace) gates a child
                # resource that has none of its own.
                if gate and not any(k in blk["body"]["attributes"] for k in ("count", "for_each")):
                    blk["body"]["attributes"].update(copy.deepcopy(gate))
            blocks.append(blk)
        if blocks:
            out[name] = {"body": {"attributes": {}, "blocks": blocks}}
    return out


class _Rewriter:
    """Rewrites a child module's expressions into its caller's namespace."""

    def __init__(self, prefix: str, inputs: dict, local_names: set, resources: set, datas: set):
        self.prefix, self.inputs = prefix, inputs
        self.local_names, self.resources, self.datas = local_names, resources, datas

    def body(self, body: dict) -> None:
        attrs = body["attributes"]
        for k in list(attrs):
            attrs[k] = self.attr(attrs[k])
        for blk in body.get("blocks", []):
            self.body(blk["body"])

    def attr(self, a: dict) -> dict:
        import copy

        src = a.get("source", "")
        m = re.fullmatch(r"\s*var\.([A-Za-z_][A-Za-z0-9_-]*)\s*", src)
        if m:  # the whole value is one input: take the caller's expression as is
            if m.group(1) in self.inputs:
                new = copy.deepcopy(self.inputs[m.group(1)])
                if "line" in a:
                    new["line"] = a["line"]
                return new
            return self._unset(a, m.group(1))
        a = dict(a)
        if "source" in a:
            a["source"] = self.text(src)
        if "refs" in a:
            refs = []
            for r in a["refs"]:
                refs.extend(self.ref_names(r))
            a["refs"] = sorted(set(refs))
        if "expr" in a:
            a["expr"] = self.node(a["expr"])
        if "items" in a:
            a["items"] = [self.attr(x) for x in a["items"] or []]
        if "fields" in a:
            a["fields"] = [{**fld, "value": self.attr(fld["value"])} for fld in a["fields"] or []]
        return a

    def _unset(self, a: dict, name: str) -> dict:
        """A required input the call does not pass (the call cannot plan):
        an unknown value, never the root's variable of the same name."""
        ref = f"module.{self.prefix}unset.{name}"
        return {**a, "source": ref, "refs": [ref], "kind": "reference",
                "expr": {"t": "ref", "steps": [{"attr": "module"}, {"attr": self.prefix + "unset"}, {"attr": name}]}}

    def ref_names(self, r: str) -> list:
        parts = r.split(".")
        if parts[0] == "var" and len(parts) > 1:
            arg = self.inputs.get(parts[1])
            return list(arg.get("refs", [])) if arg else []
        return [self.text(r)]

    _REF = re.compile(r"(?<![\w.])(?:(var|local)\.([A-Za-z_][A-Za-z0-9_-]*)"
                      r"|data\.([A-Za-z_][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_-]*)"
                      r"|([A-Za-z_][A-Za-z0-9_-]*)\.([A-Za-z_][A-Za-z0-9_-]*))")

    def text(self, s: str) -> str:
        """One pass, so a caller expression substituted for an input is never
        rewritten again."""
        def sub(mm):
            kind, name = mm.group(1), mm.group(2)
            if kind == "var":
                arg = self.inputs.get(name)
                return f"({arg['source']})" if arg and "source" in arg else f"module.{self.prefix}unset.{name}"
            if kind == "local":
                return f"local.{self.prefix}{name}" if name in self.local_names else mm.group(0)
            if mm.group(3):
                return f"data.{mm.group(3)}.{self.prefix}{mm.group(4)}" if (mm.group(3), mm.group(4)) in self.datas else mm.group(0)
            return f"{mm.group(5)}.{self.prefix}{mm.group(6)}" if (mm.group(5), mm.group(6)) in self.resources else mm.group(0)
        return self._REF.sub(sub, s)

    def node(self, n):
        if isinstance(n, list):
            return [self.node(x) for x in n]
        if not isinstance(n, dict):
            return n
        if n.get("t") == "ref":
            steps = [dict(s) for s in n.get("steps") or []]
            names = [s.get("attr") for s in steps]
            if names[:1] == ["var"] and len(steps) > 1:
                arg = self.inputs.get(names[1])
                if not arg or "expr" not in arg:
                    return {"t": "ref", "steps": [{"attr": "module"}, {"attr": self.prefix + "unset"}, *steps[1:]]}
                base, rest = arg["expr"], steps[2:]
                if not rest:
                    return base
                if base.get("t") == "ref":
                    return {"t": "ref", "steps": [*base["steps"], *rest]}
                return {"t": "rel", "src": base, "steps": rest}
            if names[:1] == ["local"] and len(steps) > 1 and names[1] in self.local_names:
                steps[1]["attr"] = self.prefix + names[1]
            elif names[:1] == ["data"] and len(steps) > 2 and (names[1], names[2]) in self.datas:
                steps[2]["attr"] = self.prefix + names[2]
            elif len(steps) > 1 and (names[0], names[1]) in self.resources:
                steps[1]["attr"] = self.prefix + names[1]
            return {**n, "steps": steps}
        return {k: self.node(v) for k, v in n.items()}


def _value(attr: dict):
    if "literal" in attr:
        return attr["literal"]
    if attr["kind"] == "tuple":
        return [_value(item) for item in attr.get("items") or []]
    if attr["kind"] == "object":
        return {f["key"]: _value(f["value"]) for f in attr.get("fields") or []}
    source = attr["source"]
    if attr["kind"] == "template" and source.startswith('"') and source.endswith('"'):
        return source[1:-1]
    if attr["kind"] == "reference" and _IDENT.match(source):
        return source
    return "${" + source + "}"


def _body(body: dict) -> dict:
    out: dict = {name: _value(attr) for name, attr in body["attributes"].items()}
    for block in body["blocks"]:
        node = _body(block["body"])
        for label in reversed(block["labels"] or []):
            node = {label: node}
        out.setdefault(block["type"], []).append(node)
    return out


def parse_dir(module_dir: Path) -> list:
    return [_body(f["body"]) for _, f in sorted(files(module_dir).items()) if "body" in f]


def parse_file(path: Path) -> dict | None:
    f = next(iter(files(path).values()), {})
    return _body(f["body"]) if "body" in f else None


def unparsed_files(module_dir: Path) -> list:
    return [name for name, f in sorted(files(module_dir).items()) if "error" in f]
