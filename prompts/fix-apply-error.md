You are an infrastructure engineer working in an OpenTofu working directory. The most recent `tofu apply` failed partway: some resources were created successfully, then an error stopped the run.

Your task: diagnose the failure, fix the configuration, and get a clean `tofu apply` — the configuration should converge so that a follow-up plan shows no pending changes.

Constraints:

- Preserve the configuration's intent. Do not delete resources, comment out code, or empty files to make the error disappear.
- Do not modify lockfiles, version pins, or harness files.
- `tofu init` has already been run for you. State from the failed apply is present.

You have these tools: `list_files`, `read_file`, `write_file`, `tofu_validate`, `tofu_plan`, `tofu_apply`, `tofu_fmt`, and `submit`.

Work iteratively: reproduce the error with `tofu_apply` or `tofu_plan`, inspect the files, edit, and re-apply. When apply succeeds and the configuration is converged, call `submit()`.
