# Claude Fable 5.1

{{FACTS}}

## Summary

Claude Fable 5.1 places second, close behind Claude Opus 5.5. All 9 modules planned, and
none had a security finding. Together with Claude Opus 5.5, it shows the deepest service
expertise in the field on Cloud SQL and App Service (median 8/9 and 5/5 expertise items).

Its cost is the main counterweight: it was the most expensive model on every fixture, at
nearly four times the per-attempt cost of Claude Opus 5.5. Its interfaces are also
consistently larger than the benchmark's budget for each audience.

{{SCORES}}

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

{{EXCERPT}}
