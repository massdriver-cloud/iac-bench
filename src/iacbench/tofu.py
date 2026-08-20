"""Thin subprocess wrapper around the tofu binary."""

from __future__ import annotations

import json
import os
import subprocess
import time
from dataclasses import dataclass, field
from pathlib import Path

DEFAULT_TIMEOUT_S = 120  # scaffold contract v1: single tofu invocation timeout

_VERSION_CACHE: str | None = None


def tofu_version() -> str:
    """The tofu binary's version, recorded into every score."""
    global _VERSION_CACHE
    if _VERSION_CACHE is None:
        try:
            out = subprocess.run(
                ["tofu", "version", "-json"], capture_output=True, text=True, timeout=30
            ).stdout
            _VERSION_CACHE = json.loads(out).get("terraform_version", "unknown")
        except (OSError, subprocess.SubprocessError, json.JSONDecodeError):
            _VERSION_CACHE = "unknown"
    return _VERSION_CACHE


@dataclass
class TofuResult:
    args: list
    exit_code: int
    stdout: str
    stderr: str
    duration_ms: int
    timed_out: bool = False


def _as_text(data) -> str:
    if data is None:
        return ""
    if isinstance(data, bytes):
        return data.decode("utf-8", errors="replace")
    return data


@dataclass
class Tofu:
    work_dir: Path
    cache_dir: Path | None = None
    timeout_s: int = DEFAULT_TIMEOUT_S
    invocations: int = 0
    history: list = field(default_factory=list)

    def _env(self) -> dict:
        env = dict(os.environ)
        env["TF_IN_AUTOMATION"] = "1"
        if self.cache_dir:
            Path(self.cache_dir).mkdir(parents=True, exist_ok=True)
            env["TF_PLUGIN_CACHE_DIR"] = str(self.cache_dir)
        return env

    def run(self, *args: str) -> TofuResult:
        self.invocations += 1
        start = time.monotonic()
        try:
            proc = subprocess.run(
                ["tofu", *args],
                cwd=self.work_dir,
                env=self._env(),
                capture_output=True,
                text=True,
                timeout=self.timeout_s,
            )
            result = TofuResult(
                args=list(args),
                exit_code=proc.returncode,
                stdout=proc.stdout,
                stderr=proc.stderr,
                duration_ms=int((time.monotonic() - start) * 1000),
            )
        except subprocess.TimeoutExpired as exc:
            result = TofuResult(
                args=list(args),
                exit_code=124,
                stdout=_as_text(exc.stdout),
                stderr=_as_text(exc.stderr) + f"\n[iacbench: tofu timed out after {self.timeout_s}s]",
                duration_ms=int((time.monotonic() - start) * 1000),
                timed_out=True,
            )
        self.history.append({"args": result.args, "exit_code": result.exit_code, "duration_ms": result.duration_ms})
        return result

    def init(self) -> TofuResult:
        return self.run("init", "-input=false", "-no-color")

    def ensure_init(self) -> TofuResult | None:
        """Run init only if providers aren't installed yet.

        Init can legitimately fail on a broken fixture (init validates config
        before installing providers), so callers must tolerate a failed init
        and let validate/plan surface the error.
        """
        if (Path(self.work_dir) / ".terraform").is_dir():
            return None
        return self.init()

    def validate(self) -> TofuResult:
        return self.run("validate", "-no-color")

    def plan(self, out_file: Path | None = None) -> TofuResult:
        args = ["plan", "-input=false", "-lock=false", "-no-color"]
        if out_file is not None:
            args.append(f"-out={out_file}")
        return self.run(*args)

    def fmt(self) -> TofuResult:
        return self.run("fmt", "-no-color")

    def apply(self) -> TofuResult:
        return self.run("apply", "-input=false", "-lock=false", "-auto-approve", "-no-color")

    def destroy(self) -> TofuResult:
        return self.run("destroy", "-input=false", "-lock=false", "-auto-approve", "-no-color")

    def plan_detailed(self) -> TofuResult:
        """Plan with -detailed-exitcode: 0 = empty plan, 2 = changes pending.

        Runs with refresh enabled, so exit 0 also verifies that state matches
        the real infrastructure — the provider's own read is the assertion.
        """
        return self.run("plan", "-input=false", "-lock=false", "-no-color", "-detailed-exitcode")

    def show_state_json(self) -> dict | None:
        result = self.run("show", "-json")
        if result.exit_code != 0:
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None

    def show_json(self, plan_file: Path) -> dict | None:
        result = self.run("show", "-json", str(plan_file))
        if result.exit_code != 0:
            return None
        try:
            return json.loads(result.stdout)
        except json.JSONDecodeError:
            return None
