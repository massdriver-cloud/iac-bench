# Kimi K3

{{FACTS}}

## Summary

Kimi K3 is the highest-scoring open-weight model in the release, placing in the second
group just behind the leaders. Its App Service median of 87 is close to the top of the
field. Its modules are heavily validated, put identity first, and split into conventional
files. Its interfaces are large.

All four of its security findings come from the same habit: a secure default that a
consumer can override through an input. On Cloud SQL, `ssl_mode` defaults to
`ENCRYPTED_ONLY`, but the validation also accepts `ALLOW_UNENCRYPTED_AND_ENCRYPTED`. This
happens in all three attempts, and the variable's description itself says the setting
should not be weakened.

{{SCORES}}

## Strengths

- **S3 hardening,** in 3/3 attempts:
  - bucket-owner-enforced ownership;
  - cleanup of incomplete multipart uploads;
  - a TLS-deny bucket policy;
  - the regional domain output.
- **Identity-first database access.** IAM database login, workload identities,
  customer-managed key support and Query Insights in 3/3 attempts. Password users are
  deliberately unsupported, and it strips the service-account suffix that Cloud SQL
  rejects.
- **Validation in depth.** 14–20 validation blocks per Cloud SQL module, including
  cross-field checks such as "point-in-time recovery requires backups."
- **Hardcoded posture on App Service.** HTTPS-only, TLS 1.2 and FTPS-off are not inputs.
  The planned attempts earned E1–E4.

## Weaknesses

- **Cloud SQL `H2` (security finding, 3/3).** The `ssl_mode` validation admits
  unencrypted connections (excerpt below). The judge scored *Anti-patterns* 0 in all three
  attempts. Here the two components agree.
- **S3 `H1` (security finding, 1/3).** One attempt adds `allow_public_read`, which turns
  off all four public-access-block settings and grants public `s3:GetObject`.
- **Failed gate on App Service (1/3).** The staging slot sets `health_check_path` without
  `health_check_eviction_time_in_min`, which the provider requires together. The production
  app sets both.
- **Large interfaces.** Over budget on S3 in 3/3 attempts and on App Service in both
  attempts that planned (27 and 34 inputs).
- **Lifecycle and pinning gaps:**
  - no database `deletion_policy` (`H11`, 3/3);
  - S3 logging without a delivery grant (`H13`, 3/3);
  - `B1` lost in 5 of the 8 attempts that planned.
- **Validation that rejects valid values.** It caps transaction-log retention at 7 days,
  but Enterprise Plus allows 35.

## Characteristic patterns

- **Secure default, open override:** the source of every security finding. The same
  posture is hardcoded on App Service, so the habit is not universal.
- **Long transcripts.** 22–49k median output tokens per attempt, the most in the field on
  Cloud SQL. Every attempt ships a README and `minimal.tfvars`.
- **Provider blocks present on GCP and Azure, absent on AWS** (`H15`, 3/3).

{{EXCERPT}}
