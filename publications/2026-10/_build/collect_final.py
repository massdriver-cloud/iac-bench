"""Collect every final-batch sample into runs/final/candidates/<fixture>/<model-tail>-e<epoch>/,
plus the current references, and write runs/final/scores.json."""
import json, shutil
from pathlib import Path
from inspect_ai.log import list_eval_logs, read_eval_log
IGN = shutil.ignore_patterns(".terraform", "*.tfplan", "*.tfstate*", ".terraform.lock.hcl", "probe-*")
root = Path("runs/final/candidates"); scores = {}
for info in list_eval_logs("logs/final"):
    log = read_eval_log(info.name)
    model = log.eval.model.split("/")[-1]
    for s in log.samples:
        md = next(iter(s.scores.values())).metadata or {}
        fx = md.get("fixture") or log.eval.task_args["fixture"]
        label = f"{model}-e{s.epoch}"
        src = Path(md["candidate_dir"].replace("/workspace/", ""))
        dst = root / fx / label
        if dst.exists(): shutil.rmtree(dst)
        shutil.copytree(src, dst, ignore=IGN)
        u = log.stats.model_usage.get(log.eval.model)
        scores.setdefault(fx, {})[label] = {
            "model": log.eval.model, "epoch": s.epoch, "log": Path(info.name).name,
            "gate": md.get("gate"), "rubric": md.get("semantic_score"), "mechanical": md.get("mechanical_score"),
            "expertise": md.get("expertise"), "items": md.get("items"), "mandatory_failures": md.get("mandatory_failures"),
            "module_sha": md.get("module_sha"), "rubric_sha": md.get("rubric_sha"), "variable_count": (md.get("stats") or {}).get("variable_count"),
            "output_tokens": s.model_usage.get(log.eval.model).output_tokens if s.model_usage.get(log.eval.model) else None,
            "seconds": s.total_time,
        }
for fx in ("G001", "G002", "G003"):
    for r in ("ref_lean", "ref_flexible"):
        dst = root / fx / r.replace("_", "-")
        if dst.exists(): shutil.rmtree(dst)
        shutil.copytree(Path("testdata/solutions") / fx / r, dst, ignore=IGN)
json.dump(scores, open("runs/final/scores.json", "w"), indent=1, default=str)
for fx, d in sorted(scores.items()): print(fx, len(d), "samples;", len(list((root/fx).iterdir())), "dirs")
