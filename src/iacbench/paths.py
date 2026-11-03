"""Repository-relative paths."""

from __future__ import annotations

import os
from pathlib import Path

REPO_ROOT = Path(os.environ.get("IACBENCH_ROOT", Path(__file__).resolve().parents[2]))
FIXTURES_DIR = REPO_ROOT / "fixtures"
SOLUTIONS_DIR = REPO_ROOT / "testdata" / "solutions"
PROMPTS_DIR = REPO_ROOT / "prompts"
RUNS_DIR = REPO_ROOT / "runs"
PROVIDER_CACHE = Path(os.environ.get("TF_PLUGIN_CACHE_DIR", REPO_ROOT / ".cache" / "providers"))


def find_fixture_dir(fixture_id: str) -> Path:
    """Locate a fixture directory by id across all domain directories."""
    for domain_dir in sorted(FIXTURES_DIR.iterdir()):
        if not domain_dir.is_dir():
            continue
        candidate = domain_dir / fixture_id
        if candidate.is_dir():
            return candidate
    raise FileNotFoundError(f"fixture {fixture_id!r} not found under {FIXTURES_DIR}")


def all_fixture_ids() -> list[str]:
    ids = []
    if FIXTURES_DIR.is_dir():
        for domain_dir in sorted(FIXTURES_DIR.iterdir()):
            if not domain_dir.is_dir():
                continue
            for fixture_dir in sorted(domain_dir.iterdir()):
                if (fixture_dir / "rubric.yaml").is_file():
                    ids.append(fixture_dir.name)
    return ids
