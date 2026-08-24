"""Inspect AI task: fix a broken OpenTofu configuration (domain: plan_failure).

Scaffold contract v1: the model gets exactly these tools — list_files,
read_file, write_file, tofu_validate, tofu_plan, tofu_fmt, plus basic_agent's
submit. No arbitrary shell. tofu init is run by the harness before turn one.

Run with e.g.:
  inspect eval src/iacbench/task.py -T fixture=F001 -T seeds=0,1,2 \
      --model anthropic/claude-sonnet-5 --epochs 5
"""

from __future__ import annotations

import asyncio
import shutil
import tempfile
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.scorer import Score, Target, accuracy, scorer, stderr
from inspect_ai.solver import TaskState, basic_agent, solver, system_message
from inspect_ai.tool import tool
from inspect_ai.util import store

# Absolute imports: inspect loads this file as a standalone module by path,
# which breaks package-relative imports.
from iacbench import CHECK_DSL_VERSION
from iacbench.checkers import (
    matches_forbidden,
    score_directory,
    score_directory_apply,
    snapshot,
)
from iacbench.manifest import FixtureManifest
from iacbench.paths import PROMPTS_DIR, PROVIDER_CACHE, RUNS_DIR, find_fixture_dir
from iacbench.render import render_fixture
from iacbench.tofu import Tofu, tofu_version

TOOL_OUTPUT_LIMIT_BYTES = 8192  # scaffold contract v1
TOFU_TIMEOUT_S = 120


def _truncate(text: str, limit: int = TOOL_OUTPUT_LIMIT_BYTES) -> str:
    data = text.encode("utf-8", errors="replace")
    if len(data) <= limit:
        return text
    return data[:limit].decode("utf-8", errors="replace") + f"\n[truncated {len(data) - limit} bytes]"


def _scratch() -> Path:
    return Path(store().get("scratch_dir"))


def _manifest() -> FixtureManifest:
    return FixtureManifest.load(Path(store().get("fixture_dir")))


def _confine(path: str) -> Path:
    """Resolve a model-supplied path inside the scratch dir or raise ValueError."""
    scratch = _scratch().resolve()
    target = (scratch / path).resolve()
    if not target.is_relative_to(scratch):
        raise ValueError(f"path escapes the working directory: {path}")
    if target != scratch and ".terraform" in target.relative_to(scratch).parts:
        raise ValueError("the .terraform directory is managed by the harness")
    return target


def _tofu(path: str = ".") -> Tofu:
    target = _confine(path)
    if not target.is_dir():
        raise ValueError(f"not a directory: {path}")
    return Tofu(target, cache_dir=PROVIDER_CACHE, timeout_s=TOFU_TIMEOUT_S)


def _record_tofu(result) -> str:
    store().set("tofu_invocations", store().get("tofu_invocations", 0) + 1)
    return _truncate(
        f"exit_code: {result.exit_code}\n"
        f"--- stdout ---\n{result.stdout}\n"
        f"--- stderr ---\n{result.stderr}"
    )


@tool
def list_files():
    async def execute(path: str = ".") -> str:
        """List files in the working directory.

        Args:
            path: Directory to list, relative to the working directory root.
        """
        try:
            target = _confine(path)
        except ValueError as exc:
            return f"ERROR: {exc}"
        if not target.is_dir():
            return f"ERROR: not a directory: {path}"
        entries = []
        for p in sorted(target.iterdir()):
            if p.name == ".terraform":
                continue
            entries.append(p.name + "/" if p.is_dir() else p.name)
        return _truncate("\n".join(entries) or "(empty)")

    return execute


@tool
def read_file():
    async def execute(path: str) -> str:
        """Read a file from the working directory.

        Args:
            path: File path relative to the working directory root.
        """
        try:
            target = _confine(path)
        except ValueError as exc:
            return f"ERROR: {exc}"
        if not target.is_file():
            return f"ERROR: no such file: {path}"
        return _truncate(target.read_text(errors="replace"))

    return execute


@tool
def write_file():
    async def execute(path: str, content: str) -> str:
        """Write a file in the working directory (whole-file replacement).

        Args:
            path: File path relative to the working directory root.
            content: Full new content of the file.
        """
        try:
            target = _confine(path)
        except ValueError as exc:
            return f"ERROR: {exc}"
        rel = target.relative_to(_scratch().resolve()).as_posix()
        if matches_forbidden(rel, store().get("forbidden_file_edits", [])):
            store().set("blocked_writes", store().get("blocked_writes", 0) + 1)
            return f"ERROR: editing {path} is not permitted"
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)
        return f"wrote {len(content.encode('utf-8'))} bytes to {rel}"

    return execute


async def _run_tofu(path: str, method: str, needs_init: bool = True, **kwargs) -> str:
    try:
        tofu = _tofu(path)
    except ValueError as exc:
        return f"ERROR: {exc}"
    if needs_init:
        init_res = await asyncio.to_thread(tofu.ensure_init)
        if init_res is not None and init_res.exit_code != 0:
            return _record_tofu(init_res)
    bound = getattr(tofu, method)
    return _record_tofu(await asyncio.to_thread(lambda: bound(**kwargs)))


@tool
def tofu_validate():
    async def execute(path: str = ".") -> str:
        """Run `tofu validate`.

        Args:
            path: Directory to run in, relative to the working directory root.
        """
        return await _run_tofu(path, "validate")

    return execute


@tool
def tofu_plan():
    async def execute(path: str = ".", var_file: str = "") -> str:
        """Run `tofu plan -input=false -lock=false`.

        Args:
            path: Directory to run in, relative to the working directory root.
            var_file: Optional tfvars file passed as -var-file, relative to the
                working directory root (e.g. "minimal.tfvars").
        """
        kwargs = {}
        if var_file:
            try:
                kwargs["var_file"] = _confine(var_file)
            except ValueError as exc:
                return f"ERROR: {exc}"
        return await _run_tofu(path, "plan", **kwargs)

    return execute


@tool
def tofu_apply():
    async def execute(path: str = ".") -> str:
        """Run `tofu apply -auto-approve`.

        Args:
            path: Directory to run in, relative to the working directory root.
        """
        return await _run_tofu(path, "apply")

    return execute


@tool
def tofu_fmt():
    async def execute(path: str = ".") -> str:
        """Run `tofu fmt`.

        Args:
            path: Directory to run in, relative to the working directory root.
        """
        return await _run_tofu(path, "fmt", needs_init=False)

    return execute


def _copy_baseline(scratch: Path, baseline: Path) -> None:
    shutil.copytree(
        scratch, baseline, symlinks=True,
        ignore=shutil.ignore_patterns(".terraform"),
    )


@solver
def setup_fixture():
    async def solve(state: TaskState, generate):
        fixture_id = state.metadata["fixture"]
        seed = int(state.metadata["seed"])
        fixture_dir = find_fixture_dir(fixture_id)
        manifest = FixtureManifest.load(fixture_dir)

        scratch_root = RUNS_DIR / "scratch"
        scratch_root.mkdir(parents=True, exist_ok=True)
        scratch = Path(tempfile.mkdtemp(prefix=f"{fixture_id}-seed{seed}-", dir=scratch_root))

        ctx = render_fixture(manifest, seed, scratch)
        # Init may fail on fixtures broken at init time; the tofu tools and
        # the scorer re-run init lazily once the config is fixable.
        setup_tofu = Tofu(scratch, cache_dir=PROVIDER_CACHE, timeout_s=300)
        await asyncio.to_thread(setup_tofu.init)

        baseline = scratch.parent / (scratch.name + "-baseline")
        _copy_baseline(scratch, baseline)

        # Tier-2 fixtures start from a failed apply: real resources partially
        # exist and the error is in the apply output the model can reproduce.
        if manifest.tier == 2:
            await asyncio.to_thread(setup_tofu.apply)

        store().set("fixture_dir", str(fixture_dir))
        store().set("scratch_dir", str(scratch))
        store().set("baseline_dir", str(baseline))
        store().set("baseline_snapshot", snapshot(scratch))
        store().set("seed_context", ctx)
        store().set("forbidden_file_edits", manifest.forbidden_file_edits)
        store().set("blocked_writes", 0)
        store().set("tofu_invocations", 0)
        return state

    return solve


@solver
def setup_generation():
    """Generation fixtures start from an empty working directory."""

    async def solve(state: TaskState, generate):
        fixture_id = state.metadata["fixture"]
        fixture_dir = find_fixture_dir(fixture_id)
        scratch_root = RUNS_DIR / "scratch"
        scratch_root.mkdir(parents=True, exist_ok=True)
        scratch = Path(tempfile.mkdtemp(prefix=f"{fixture_id}-", dir=scratch_root))
        store().set("fixture_dir", str(fixture_dir))
        store().set("scratch_dir", str(scratch))
        store().set("forbidden_file_edits", [])
        store().set("blocked_writes", 0)
        store().set("tofu_invocations", 0)
        return state

    return solve


@scorer(metrics=[accuracy(), stderr()])
def generation_scorer():
    async def score(state: TaskState, target: Target) -> Score:
        from iacbench.generation import GenerationFixture, score_generation

        fixture = GenerationFixture.load(Path(store().get("fixture_dir")))
        scratch = _scratch()
        result = await asyncio.to_thread(
            score_generation, fixture, scratch, scratch.parent / (scratch.name + "-probes")
        )
        return Score(
            value=result.semantic_score,
            answer=result.verdict,
            explanation="; ".join(result.details) or "all rubric items passed",
            metadata={
                "gate": result.gate,
                "items": result.items,
                "semantic_score": result.semantic_score,
                "mechanical_score": result.mechanical_score,
                "scoring_policy": result.scoring_policy,
                "stats": result.stats,
                "expertise": result.expertise,
                "expertise_score": result.expertise_score,
                "mandatory_failures": result.mandatory_failures,
                "probe_plans": result.probe_plans,
                "module_sha": result.module_sha,
                "check_dsl_version": CHECK_DSL_VERSION,
                "fixture": fixture.id,
                "tofu_version": tofu_version(),
            },
        )

    return score


@task
def generate_module(
    fixture: str = "G001",
    message_limit: int = 150,
    time_limit: int = 1800,
):
    """Tier 2 generation: build a module from a brief; scored by the fixture rubric.

    Plan-only — requires AWS credentials but creates no resources.
    """
    from iacbench.generation import GenerationFixture

    gen = GenerationFixture.load(find_fixture_dir(fixture))
    prompt = (PROMPTS_DIR / "generate-module.md").read_text()
    samples = [Sample(id=fixture, input=gen.brief, metadata={"fixture": fixture, "seed": 0})]
    return Task(
        dataset=samples,
        solver=[
            setup_generation(),
            basic_agent(
                init=system_message(prompt),
                tools=[
                    list_files(),
                    read_file(),
                    write_file(),
                    tofu_validate(),
                    tofu_plan(),
                    tofu_fmt(),
                ],
                max_attempts=1,
            ),
        ],
        scorer=generation_scorer(),
        message_limit=message_limit,
        time_limit=time_limit,
    )


@scorer(metrics=[accuracy(), stderr()])
def invariants():
    async def score(state: TaskState, target: Target) -> Score:
        manifest = _manifest()
        result = await asyncio.to_thread(
            score_directory,
            manifest,
            store().get("seed_context"),
            Path(store().get("baseline_dir")),
            store().get("baseline_snapshot"),
            _scratch(),
            store().get("blocked_writes", 0),
            tofu=Tofu(_scratch(), cache_dir=PROVIDER_CACHE, timeout_s=TOFU_TIMEOUT_S),
        )
        return Score(
            value=1.0 if result.passed else 0.0,
            answer=result.verdict,
            explanation=result.failure_detail or "all invariants passed",
            metadata={
                "invariants": result.invariants,
                "efficiency": result.efficiency,
                "planned_addresses": result.planned_addresses,
                "blocked_writes": store().get("blocked_writes", 0),
                "tool_tofu_invocations": store().get("tofu_invocations", 0),
                "fixture": manifest.id,
                "seed": store().get("seed_context", {}).get("seed"),
                "tofu_version": tofu_version(),
            },
        )

    return score


@scorer(metrics=[accuracy(), stderr()])
def invariants_apply():
    async def score(state: TaskState, target: Target) -> Score:
        manifest = _manifest()
        tofu = Tofu(_scratch(), cache_dir=PROVIDER_CACHE, timeout_s=300)
        try:
            result = await asyncio.to_thread(
                score_directory_apply,
                manifest,
                store().get("seed_context"),
                Path(store().get("baseline_dir")),
                store().get("baseline_snapshot"),
                _scratch(),
                store().get("blocked_writes", 0),
                tofu=tofu,
            )
        finally:
            # Cleanup is the cost guardrail: always destroy, record the outcome.
            destroy_res = await asyncio.to_thread(tofu.destroy)
        return Score(
            value=1.0 if result.passed else 0.0,
            answer=result.verdict,
            explanation=result.failure_detail or "all invariants passed",
            metadata={
                "invariants": result.invariants,
                "efficiency": result.efficiency,
                "state_addresses": result.planned_addresses,
                "blocked_writes": store().get("blocked_writes", 0),
                "tool_tofu_invocations": store().get("tofu_invocations", 0),
                "destroy_clean": destroy_res.exit_code == 0,
                "fixture": manifest.id,
                "seed": store().get("seed_context", {}).get("seed"),
                "tofu_version": tofu_version(),
            },
        )

    return score


@task
def fix_apply_failure(
    fixture: str = "F101",
    seeds: str = "0",
    message_limit: int = 90,
    time_limit: int = 900,
):
    """Tier 2: diagnose and fix a configuration whose apply failed partway.

    Requires AWS credentials in the environment. Toolset: the plan-failure
    tools plus tofu_apply.
    """
    seed_list = [int(s) for s in str(seeds).split(",")]
    prompt = (PROMPTS_DIR / "fix-apply-error.md").read_text()
    samples = [
        Sample(
            id=f"{fixture}-seed{seed}",
            input=(
                "The most recent `tofu apply` in your working directory failed partway: "
                "some resources were created, then an error stopped the run. Diagnose the "
                "failure, fix the configuration, apply it cleanly, and submit when done."
            ),
            metadata={"fixture": fixture, "seed": seed},
        )
        for seed in seed_list
    ]
    return Task(
        dataset=samples,
        solver=[
            setup_fixture(),
            basic_agent(
                init=system_message(prompt),
                tools=[
                    list_files(),
                    read_file(),
                    write_file(),
                    tofu_validate(),
                    tofu_plan(),
                    tofu_apply(),
                    tofu_fmt(),
                ],
                max_attempts=1,
            ),
        ],
        scorer=invariants_apply(),
        message_limit=message_limit,
        time_limit=time_limit,
    )


@task
def fix_plan_failure(
    fixture: str = "F001",
    seeds: str = "0",
    message_limit: int = 90,
    time_limit: int = 600,
):
    seed_list = [int(s) for s in str(seeds).split(",")]
    prompt = (PROMPTS_DIR / "fix-plan-error.md").read_text()
    samples = [
        Sample(
            id=f"{fixture}-seed{seed}",
            input=(
                "The OpenTofu configuration in your working directory fails to plan. "
                "Diagnose the failure, fix the configuration, and submit when done."
            ),
            metadata={"fixture": fixture, "seed": seed},
        )
        for seed in seed_list
    ]
    return Task(
        dataset=samples,
        solver=[
            setup_fixture(),
            basic_agent(
                init=system_message(prompt),
                tools=[
                    list_files(),
                    read_file(),
                    write_file(),
                    tofu_validate(),
                    tofu_plan(),
                    tofu_fmt(),
                ],
                max_attempts=1,
            ),
        ],
        scorer=invariants(),
        message_limit=message_limit,
        time_limit=time_limit,
    )
