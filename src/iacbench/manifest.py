"""Fixture manifest (fixture.yaml) parsing."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml


@dataclass
class FixtureManifest:
    id: str
    domain: str
    suite_version: str
    visibility: str
    error_class: str
    error_pattern: str
    description: str
    seed_params: dict
    required_addresses: list
    forbidden_file_edits: list
    removable_addresses: list
    min_resource_count: int
    tier: int
    path: Path

    @classmethod
    def load(cls, fixture_dir: Path) -> FixtureManifest:
        fixture_dir = Path(fixture_dir)
        data = yaml.safe_load((fixture_dir / "fixture.yaml").read_text())
        return cls(
            id=data["id"],
            domain=data["domain"],
            suite_version=data["suite_version"],
            visibility=data.get("visibility", "public"),
            error_class=data["error_class"],
            error_pattern=data["error_pattern"],
            description=data.get("description", ""),
            seed_params=data.get("seed_params", {}),
            required_addresses=data.get("required_addresses", []),
            forbidden_file_edits=data.get("forbidden_file_edits", []),
            removable_addresses=data.get("removable_addresses", []),
            min_resource_count=data.get("min_resource_count", 0),
            tier=data.get("tier", 1),
            path=fixture_dir,
        )

    @property
    def template_dir(self) -> Path:
        return self.path / "template"
