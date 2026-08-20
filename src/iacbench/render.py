"""Deterministic seeded rendering of fixture templates.

Files ending in .j2 are rendered with Jinja2 (suffix stripped); everything else
is copied verbatim. Rendering the same (fixture, seed) twice must produce
byte-identical output — selftest asserts this.
"""

from __future__ import annotations

import shutil
from pathlib import Path

import jinja2

from .manifest import FixtureManifest


def seed_context(manifest: FixtureManifest, seed: int) -> dict:
    """Map a seed to one concrete value per seed_param.

    Mixed-radix digit extraction (params in sorted name order) rather than a
    PRNG, so the mapping is stable across Python versions and reimplementable
    in any language: seed=0 always selects the first value of every param.
    """
    ctx: dict = {"seed": seed}
    radix = 1
    for name in sorted(manifest.seed_params):
        values = manifest.seed_params[name]
        ctx[name] = values[(seed // radix) % len(values)]
        radix *= len(values)
    return ctx


def render_fixture(manifest: FixtureManifest, seed: int, out_dir: Path) -> dict:
    """Render the fixture's template into out_dir; returns the seed context."""
    ctx = seed_context(manifest, seed)
    out_dir = Path(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    env = jinja2.Environment(
        loader=jinja2.FileSystemLoader(str(manifest.template_dir)),
        undefined=jinja2.StrictUndefined,
        keep_trailing_newline=True,
    )
    for src in sorted(manifest.template_dir.rglob("*")):
        if src.is_dir():
            continue
        rel = src.relative_to(manifest.template_dir)
        dest = out_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        if src.name.endswith(".j2"):
            rendered = env.get_template(rel.as_posix()).render(ctx)
            dest = dest.with_name(dest.name[: -len(".j2")])
            dest.write_text(rendered)
        else:
            shutil.copyfile(src, dest)
    return ctx


def render_address(address_template: str, ctx: dict) -> str:
    """Render a seed-parameterized resource address from the manifest."""
    return jinja2.Template(address_template, undefined=jinja2.StrictUndefined).render(ctx)
