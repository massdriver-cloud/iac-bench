"""iacbench CLI: render and selftest. Evals run via `inspect eval` (see README)."""

from __future__ import annotations

import argparse
from pathlib import Path

from .manifest import FixtureManifest
from .paths import RUNS_DIR, find_fixture_dir
from .render import render_fixture
from .selftest import run_selftest


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="iacbench")
    sub = parser.add_subparsers(dest="command", required=True)

    p_render = sub.add_parser("render", help="render a fixture into a directory")
    p_render.add_argument("--fixture", required=True)
    p_render.add_argument("--seed", type=int, default=0)
    p_render.add_argument("--out", required=True)

    p_selftest = sub.add_parser("selftest", help="validate checkers against known-answer solutions")
    p_selftest.add_argument("--fixture", action="append", help="limit to a fixture id (repeatable)")

    p_report = sub.add_parser("report", help="render markdown report with Wilson intervals from eval logs")
    p_report.add_argument("--log-dir", default="logs")
    p_report.add_argument("--out", default=None, help="output file (default: print to stdout)")
    p_report.add_argument(
        "--judge-dir", action="append", default=None,
        help="judge output dir (repeatable); adds a pairwise-ranking section",
    )

    p_sweep = sub.add_parser("sweep", help="find (and optionally delete) leaked iacbench-tagged AWS resources")
    p_sweep.add_argument("--region", default=None, help="AWS region (default: AWS_REGION or us-east-1)")
    p_sweep.add_argument("--delete", action="store_true", help="delete what is found (S3 supported)")

    p_judge = sub.add_parser("judge", help="pairwise LLM judging of generation candidates (experimental layer)")
    p_judge.add_argument("--fixture", default="G001")
    p_judge.add_argument("--candidates", help="directory containing one module subdirectory per candidate")
    p_judge.add_argument("--model", default="anthropic/claude-opus-5", help="judge model")
    p_judge.add_argument("--rounds", type=int, default=1, help="judgments per pair per presentation order")
    p_judge.add_argument("--out", default=None, help="output dir (default: runs/judge/<fixture>)")
    p_judge.add_argument(
        "--human", default=None,
        help="human calibration yaml: pairs (pairwise mode) or grades (with --grade); "
             "computes judge-vs-human agreement and updates the stored status",
    )
    p_judge.add_argument("--grade", action="store_true", help="absolute grading mode: score each candidate 0-100 against good-opentofu.md, no comparisons")
    p_judge.add_argument("--samples", type=int, default=3, help="grading samples per candidate (grade mode)")

    p_cal = sub.add_parser(
        "calibrate",
        help="evidence-assisted judge calibration: packets -> human verdicts -> adjudicate -> finalize",
    )
    p_cal.add_argument("stage", choices=["packets", "adjudicate", "finalize"])
    p_cal.add_argument("--fixture", default="G001")
    p_cal.add_argument("--candidates", help="directory of candidate module dirs (packets stage)")
    p_cal.add_argument("--judge-dir", required=True, help="dir with judgments.jsonl + scores.json")
    p_cal.add_argument("--out", required=True, help="calibration working directory")

    args = parser.parse_args(argv)

    if args.command == "render":
        manifest = FixtureManifest.load(find_fixture_dir(args.fixture))
        ctx = render_fixture(manifest, args.seed, Path(args.out))
        print(f"rendered {manifest.id} seed={args.seed} -> {args.out}")
        for key, value in sorted(ctx.items()):
            print(f"  {key} = {value}")
        return 0

    if args.command == "selftest":
        return run_selftest(args.fixture)

    if args.command == "report":
        from .report import run_report

        judge_dirs = [Path(d) for d in (args.judge_dir or [])]
        return run_report(Path(args.log_dir), Path(args.out) if args.out else None, judge_dirs)

    if args.command == "sweep":
        import os

        from .sweep import run_sweep

        return run_sweep(args.region or os.environ.get("AWS_REGION", "us-east-1"), args.delete)

    if args.command == "calibrate":
        import json
        import shutil
        import tempfile

        from . import calibrate
        from .generation import GenerationFixture, score_generation

        out_dir = Path(args.out)
        judge_dir = Path(args.judge_dir)
        if args.stage == "packets":
            if not args.candidates:
                print("packets stage requires --candidates")
                return 1
            fixture = GenerationFixture.load(find_fixture_dir(args.fixture))
            candidates = {
                d.name: d for d in sorted(Path(args.candidates).iterdir()) if d.is_dir()
            }
            scores = json.loads((judge_dir / "scores.json").read_text())
            pairs = calibrate.select_pairs(scores["bt_scores"])
            findings: dict = {}
            with tempfile.TemporaryDirectory(prefix="iacbench-calib-") as tmp:
                for label, d in candidates.items():
                    module_copy = Path(tmp) / label / "module"
                    shutil.copytree(d, module_copy)
                    print(f"scoring {label} for mechanical findings...", flush=True)
                    findings[label] = score_generation(fixture, module_copy, Path(tmp) / label / "work")
            verdicts = calibrate.write_packets(fixture, candidates, findings, pairs, out_dir)
            print(f"wrote {len(pairs)} packets under {out_dir / 'pairs'}")
            print(f"fill in {verdicts} (winner per pair), then run the adjudicate stage")
            return 0
        if args.stage == "adjudicate":
            summary = calibrate.adjudicate(out_dir / "verdicts.yaml", judge_dir, out_dir)
            print(json.dumps(summary, indent=2))
            if summary["disagree"]:
                print(f"\nresolve uphold/reason in {summary['adjudication']}, then run finalize")
            return 0
        if args.stage == "finalize":
            result = calibrate.finalize(out_dir / "verdicts.yaml", out_dir / "adjudication.yaml", judge_dir)
            print(json.dumps(result, indent=2))
            if result.get("unresolved_disagreements"):
                print("\nunresolved disagreements remain — fill uphold/reason and re-run")
                return 1
            return 0

    if args.command == "judge":
        import asyncio
        import json

        from .generation import GenerationFixture
        from .judge import agreement, run_judge

        out_dir = Path(args.out) if args.out else RUNS_DIR / "judge" / args.fixture
        if args.grade:
            from .judge import grade_agreement, run_grade

            if not args.candidates and not args.human:
                print("--grade requires --candidates (to grade) and/or --human (to calibrate)")
                return 1
            if args.candidates:
                fixture = GenerationFixture.load(find_fixture_dir(args.fixture))
                candidates = {
                    d.name: d for d in sorted(Path(args.candidates).iterdir()) if d.is_dir()
                }
                summary = asyncio.run(
                    run_grade(fixture.id, fixture.brief, candidates, args.model, out_dir, args.samples)
                )
                print(json.dumps(summary["grades"], indent=2))
            if args.human:
                result = grade_agreement(out_dir / "grades.json", Path(args.human))
                print(json.dumps(result, indent=2))
                if result["agreement"] is not None and result["agreement"] < 0.8:
                    print("\nabsolute grading is NOT calibrated (spearman < 0.8) — "
                          "the report will keep grades out of the composite")
                    return 1
            return 0
        if args.candidates:
            fixture = GenerationFixture.load(find_fixture_dir(args.fixture))
            candidates = {
                d.name: d for d in sorted(Path(args.candidates).iterdir()) if d.is_dir()
            }
            if len(candidates) < 2:
                print(f"need at least 2 candidate module dirs under {args.candidates}")
                return 1
            summary = asyncio.run(
                run_judge(fixture.id, fixture.brief, candidates, args.model, out_dir, args.rounds)
            )
            print(json.dumps(summary, indent=2))
        if args.human:
            result = agreement(out_dir / "judgments.jsonl", Path(args.human))
            print(json.dumps(result, indent=2))
            scores_path = out_dir / "scores.json"
            if scores_path.is_file() and result["agreement"] is not None:
                data = json.loads(scores_path.read_text())
                data["agreement"] = result["agreement"]
                data["graded_pairs"] = result["graded_pairs"]
                data["status"] = (
                    "calibrated" if result["agreement"] >= 0.8
                    else "experimental (failed calibration)"
                )
                scores_path.write_text(json.dumps(data, indent=2))
            if result["agreement"] is not None and result["agreement"] < 0.8:
                print("\njudge is NOT calibrated (agreement < 0.8) — keep its column experimental")
                return 1
        if not args.candidates and not args.human:
            print("nothing to do: pass --candidates to judge, --human to check calibration, or both")
            return 2
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main())
