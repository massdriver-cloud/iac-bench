---
title: "Claude Fable 5.1: iac-bench 2026-10"
release: "2026-10"
---

# Claude Fable 5.1

| | |
|---|---|
| Developer | Anthropic |
| API identifier | `claude-fable-5-1` |
| Access | Anthropic API |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 10.00 / 50.00 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **86.9** (95% CI 83.7–90.2) |
| Rank | 2 of 10 (95% rank interval 1–5) |
| Mechanical only / judge only | 85.0 (rank 2) / 91.2 (rank 5) |
| Failed gates · insecure attempts | 0/9 · 0/9 |
| Estimated cost, all 9 attempts | $13.97 |

## Summary

Claude Fable 5.1 places second, close behind Claude Opus 5.5. All 9 modules planned, and
none had a security finding. Together with Claude Opus 5.5, it shows the deepest service
expertise in the field on Cloud SQL and App Service (median 8/9 and 5/5 expertise items).

Its cost is the main counterweight: it was the most expensive model on every fixture, at
nearly four times the per-attempt cost of Claude Opus 5.5. Its interfaces are also
consistently larger than the benchmark's budget for each audience.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 85.6 (82.6–90.2) | 0.826 | 6/7 | 92.1 | 0/3 | 0/3 | 12 | 12,112 | 302 s | $0.935 |
| G002 · Cloud SQL | 85.6 (79.0–90.0) | 0.832 | 8/9 | 94.7 | 0/3 | 0/3 | 30 | 14,402 | 196 s | $1.229 |
| G003 · App Service | 89.5 (88.5–94.9) | 0.911 | 5/5 | 86.8 | 0/3 | 0/3 | 28 | 27,308 | 566 s | $2.157 |

Rubric items not at full credit, counted over attempts that planned: G001: `A5` 3/3, `B1` 3/3, `H12` 2/3, `H13` 3/3, `H15` 1/3; G002: `A8` 3/3, `B1` 3/3, `H4` 3/3, `H5` 3/3, `H10` 1/3, `H11` 3/3; G003: `A7` 3/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **No security setting is ever an input** (all 9 attempts passed every mandatory item).
  The judge scored *Anti-patterns* 2 in every attempt.
- **Expertise coverage:**
  - App Service: E1–E4 in 3/3 attempts, plus Key Vault references (E5) in 2/3. Opus is
    the only other model with full G003 expertise.
  - Cloud SQL: IAM login, workload identities, managed databases and users, the
    connection audit trail and Query Insights, all in 3/3 attempts.
- **Concept-level interfaces.** On Cloud SQL, a single `environment` input sets the
  network (`apps-<env>`), the HA type and backup retention.
- **Strict guards.** 6–16 validation blocks per module, plus cross-input preconditions.
  These include a `terraform_data` guard on App Service that holds five capacity rules.

## Weaknesses

- **Interfaces are over budget on every fixture:**
  - S3: `A5`, 11–13 inputs against 8.
  - Cloud SQL: `A8`, 26–37 inputs against 25. One attempt scored zero.
  - App Service: `A7`, 27–29 inputs against 20.
  - The judge flagged the S3 interface too: *Interface design* 1 in 5 of 9 readings, for
    knobs such as `intelligent_tiering_after_days`.
- **Provider constraints that admit a new major:** unbounded `>=`, or `>= 5.30, < 7.0`, in
  6 of 9 attempts (`B1`).
- **Cloud SQL drops databases that are removed from the input** (`H11` lost in 3/3). One
  attempt adds a `deletion_policy` input, but its default is `DELETE`. One attempt also
  writes a break-glass password into state (`H10`).
- **S3 access logging that cannot deliver.** No sample grants the logging service
  permission to write (`H13`, 3/3).
- **Documentation errors in long READMEs.** For example, it states 1–35 days of WAL
  retention for the Enterprise edition, which allows 1–7. These earned *Documentation* 0 in
  two Cloud SQL attempts.

## Characteristic patterns

- **It writes a README every time,** usually with a table separating the decisions the
  module fixes from the ones it leaves to the caller. The extra volume is where most of its
  documentation errors come from.
- **It splits files by concern as modules grow** (`observability.tf`, `scaling.tf`,
  `slot.tf`), but still lets `main.tf` grow past 200 lines in 4/9 attempts.
- **It uses `for_each` for multiplicity and `count` only as a switch.** The judge gave
  *Iteration* and *Internal logic* 2 in all 9 attempts.

## Representative excerpt

`G002/claude-fable-5-1-e1/main.tf` lines 11–21

```hcl
  # Flags that are the same on every instance and cannot be overridden by callers.
  enforced_database_flags = {
    "cloudsql.iam_authentication" = "on"
    "log_connections"             = "on"
    "log_disconnections"          = "on"
    "log_checkpoints"             = "on"
    "log_lock_waits"              = "on"
    "log_temp_files"              = "0"
  }

  database_flags = merge(var.database_flags, local.enforced_database_flags)
```

The same pattern as the leader, with a broader enforced audit set: connections, disconnections, checkpoints, lock waits and temporary files are always logged.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
