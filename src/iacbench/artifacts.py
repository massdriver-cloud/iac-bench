"""Content addressing for scored module artifacts.

The rubric score (from an eval log) and the judge grade (from a snapshotted
candidates directory) are computed at different times over what must be the
same module. Both record this hash so the report can refuse to join scores
that belong to different artifacts.
"""

from __future__ import annotations

import hashlib
from pathlib import Path

_SKIP_DIRS = {".terraform"}
_SKIP_PREFIXES = ("probe-",)


def module_sha(module_dir: Path) -> str:
    """Order-independent sha256 over the module's file names and contents,
    excluding harness artifacts (.terraform, probe files, lockfile)."""
    h = hashlib.sha256()
    module_dir = Path(module_dir)
    for path in sorted(module_dir.rglob("*")):
        if not path.is_file():
            continue
        rel = path.relative_to(module_dir)
        if any(part in _SKIP_DIRS for part in rel.parts):
            continue
        if rel.name.startswith(_SKIP_PREFIXES) or rel.name == ".terraform.lock.hcl":
            continue
        h.update(rel.as_posix().encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return h.hexdigest()[:16]
