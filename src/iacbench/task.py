"""Inspect AI task: write an OpenTofu module from a brief (generation).

Scaffold contract v1: the model gets exactly these tools — list_files,
read_file, write_file, tofu_validate, tofu_plan, tofu_fmt, plus basic_agent's
submit. No arbitrary shell. The module is scored by the fixture's rubric
(generation.py), plan-only.

Run with e.g.:
  inspect eval src/iacbench/task.py@generate_module -T fixture=G001 \
      --model anthropic/claude-sonnet-5 --epochs 3
"""

from __future__ import annotations

import asyncio
import tempfile
from pathlib import Path

from inspect_ai import Task, task
from inspect_ai.dataset import Sample
from inspect_ai.model import GenerateConfig
from inspect_ai.scorer import Score, Target, accuracy, scorer, stderr
from inspect_ai.solver import TaskState, basic_agent, solver, system_message
from inspect_ai.tool import tool
from inspect_ai.util import store

# Absolute imports: inspect loads this file as a standalone module by path,
# which breaks package-relative imports.
from iacbench import CHECK_DSL_VERSION
from iacbench.paths import PROMPTS_DIR, PROVIDER_CACHE, RUNS_DIR, find_fixture_dir
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
def tofu_fmt():
    async def execute(path: str = ".") -> str:
        """Run `tofu fmt`.

        Args:
            path: Directory to run in, relative to the working directory root.
        """
        return await _run_tofu(path, "fmt", needs_init=False)

    return execute


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
                "rubric_sha": fixture.rubric_sha,
                "stats": result.stats,
                "expertise": result.expertise,
                "expertise_score": result.expertise_score,
                "mandatory_failures": result.mandatory_failures,
                "probe_plans": result.probe_plans,
                "module_sha": result.module_sha,
                # Where the generated module lives, so judge and calibration
                # can collect it as a candidate.
                "candidate_dir": str(scratch),
                "check_dsl_version": CHECK_DSL_VERSION,
                "fixture": fixture.id,
                "tofu_version": tofu_version(),
            },
        )

    return score


# A model API that keeps failing (exhausted quota, outage) must end the sample
# as an error, never run out the clock and get scored as a real 0.
API_RETRY_CONFIG = GenerateConfig(max_retries=3)


@task
def generate_module(
    fixture: str = "G001",
    message_limit: int = 150,
    time_limit: int = 1800,
):
    """Build a module from a brief; scored by the fixture rubric.

    Plan-only — requires credentials for the cloud the fixture declares, but
    creates no resources.
    """
    from iacbench.generation import GenerationFixture

    gen = GenerationFixture.load(find_fixture_dir(fixture))
    prompt = (PROMPTS_DIR / "generate-module.md").read_text()
    samples = [Sample(id=fixture, input=gen.brief, metadata={"fixture": fixture})]
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
        config=API_RETRY_CONFIG,
    )
