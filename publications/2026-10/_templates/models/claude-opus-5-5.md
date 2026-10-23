# Claude Opus 5.5

{{FACTS}}

## Summary

Claude Opus 5.5 has the highest overall score in the 2026-10 release. It is the only model
whose 95% rank interval stays within the top three. All 9 of its modules planned, and none
failed a mandatory security item. Its weakest attempt (85.0) is the strongest
worst case of any model in the release. Its overall lead over Claude Fable 5.1 and GPT-6 Astra is within the margin of
three samples (bootstrap win probability about 0.85 against each). The clearer distinction is
consistency: no fixture produced a weak attempt.

Its modules fix the security settings in code and do not offer them as inputs. They derive
values from a small set of concept inputs, and they include most of the service-specific
practices the benchmark checks for: 7/7 on S3, 8/9 on Cloud SQL and 5/5 on App Service, in
every sample.

{{SCORES}}

## Strengths

- **Security posture is never an input.**
  - S3: the public access block, bucket-owner-enforced ownership and a deny on non-TLS
    requests are hardcoded.
  - Cloud SQL: `ipv4_enabled = false` and `ssl_mode = "ENCRYPTED_ONLY"` are literals.
  - App Service: HTTPS-only, disabled basic-auth publishing and TLS 1.2 minimums are set on
    the app and the slot.
- **Settings that consumers cannot weaken.** On Cloud SQL the DBA team gets an open-ended
  `database_flags` input. The module merges its own required flags (IAM authentication,
  pgaudit, connection logging) last, so no input can turn them off (excerpt below).
- **Identity instead of credentials, on all three clouds:**
  - ready-made read-only and read-write IAM policy documents for S3 consumers;
  - IAM-only Cloud SQL users, with no password users created;
  - managed-identity image pulls with an AcrPull grant on Azure.
- **Validation with cross-input checks.** For example, `force_destroy` is refused in
  production, and on Cloud SQL the Enterprise Plus log retention is checked against the
  edition.

## Weaknesses

- **Interface size on the specialist fixtures.**
  - Cloud SQL: 26–30 inputs, over the 25-input budget, so `A8` is lost in 3/3.
  - App Service: 25–29 inputs, over the 20-input budget, so `A7` is lost in 3/3.
  - The judge rated the same interfaces as appropriate for the audience (*Interface
    design* 2), which shows the two components measuring audience fit differently.
- **Data protection on Cloud SQL is all or nothing.**
  - Databases removed from the input are dropped: no `deletion_policy` (`H11` lost in
    3/3).
  - Backups and point-in-time recovery are on with no opt-out, so `H4` and `H5` earn
    partial credit.
  - In one sample, deletion protection is hardcoded with no way to retire the instance
    (`H3`).
- **S3 access logging that cannot deliver.** No sample grants the logging service
  permission to write (`H13`, 3/3), and two of three offer no access logging at all (`H9`).
- **Provider constraints spanning two majors.** `>= 5.0, < 7.0`, or unbounded `>= 5.0`,
  in 5/9 attempts (`B1`).
- **Judge deductions on App Service:**
  - unconditional `ignore_changes = [worker_count]`;
  - a registry URL input that can conflict with the registry ID;
  - in one sample, descriptions that contradict the code (*Documentation* 0).

## Characteristic patterns

- **It hardcodes and derives rather than adding inputs.** On Cloud SQL the network comes
  from `environment` (`apps-${var.environment}`), and so does high availability.
- **It adds inputs in proportion to the audience:** median inputs of 10, 29 and 28 on the
  three fixtures.
- **One `main.tf` by default.** It splits monitoring or diagnostics into separate files
  only on App Service, and only in some samples. The judge gave *File layout* 1 in 6/9
  attempts.
- **It documents in variable descriptions rather than READMEs.** 1/9 attempts ship a
  README.

{{EXCERPT}}

## Notes on the judge

The judge is Claude Opus 5.5, so this page grades the judge's own model. Its grades for
this model are 97.4 (S3) and 100 (Cloud SQL). Without the judge, ranking on the mechanical
score alone, Claude Opus 5.5 still ranks first (86.4), so the top of the ranking does not
depend on the judge. See [Methodology §5.3](../methodology.md#53-known-judge-risks).
