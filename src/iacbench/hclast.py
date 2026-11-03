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
    *.tf files or for one .tf/.tfvars file."""
    path = Path(path).resolve()
    return _files(str(path), _stamp(path))


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
