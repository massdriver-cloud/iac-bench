"""Re-score every sample of the named eval logs under the current engine and
write corrected logs; originals move to logs/final-superseded/."""
import shutil, sys, tempfile
from pathlib import Path
from inspect_ai.log import read_eval_log, write_eval_log
from iacbench.generation import GenerationFixture, score_generation
from iacbench.paths import find_fixture_dir
COMMIT, REASON = sys.argv[1], sys.argv[2]
Path("logs/final-superseded").mkdir(exist_ok=True)
for name in sys.argv[3:]:
    src = Path("logs/final") / name
    log = read_eval_log(str(src))
    for s in log.samples:
        sc = next(iter(s.scores.values())); md = dict(sc.metadata or {})
        fx = GenerationFixture.load(find_fixture_dir(md["fixture"]))
        cand = Path(md["candidate_dir"].replace("/workspace/", ""))
        work = Path(tempfile.mkdtemp()); shutil.copytree(cand, work / "m", ignore=shutil.ignore_patterns(".terraform", "probe-*", "*.tfplan", "*.tfstate*"))
        r = score_generation(fx, work / "m", work / "probes")
        assert r.module_sha == md["module_sha"], (name, s.epoch, "module changed")
        before = (sc.value, md.get("mandatory_failures"))
        md.update({"gate": r.gate, "items": r.items, "semantic_score": r.semantic_score, "mechanical_score": r.mechanical_score,
                   "rubric_sha": fx.rubric_sha, "stats": r.stats, "expertise": r.expertise, "expertise_score": r.expertise_score,
                   "mandatory_failures": r.mandatory_failures, "probe_plans": r.probe_plans,
                   "rescored": {"engine_commit": COMMIT, "reason": REASON, "previous_value": before[0], "previous_mandatory_failures": before[1]}})
        sc.value = r.semantic_score; sc.answer = r.verdict; sc.metadata = md
        sc.explanation = "; ".join(r.details) or "all rubric items passed"
        print(f"{name[-20:]} e{s.epoch}: {before[0]:.3f} {before[1]} -> {r.semantic_score:.3f} {r.mandatory_failures}")
    shutil.move(str(src), Path("logs/final-superseded") / name)
    write_eval_log(log, str(src))
