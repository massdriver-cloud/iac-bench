# Claude Sonnet 5.5

{{FACTS}}

## Summary

Claude Sonnet 5.5 is in the top group overall. Its Cloud SQL result (G002) is second only to
GPT-6 Astra's, by under one point. It is the cheapest model in that group, at roughly a tenth of the
per-attempt cost of Claude Fable 5.1. All 9 attempts planned.

Its two security findings come from a single omission on App Service: in 2 of 3 attempts it
never sets the two basic-auth publishing flags, which the Azure provider enables by default.
The same blocks set HTTPS-only, TLS 1.2 and FTPS-off correctly.

{{SCORES}}

## Strengths

- **Locked posture on Cloud SQL (3/3).** It sets private IP only and `ENCRYPTED_ONLY`, and
  merges consumer flags *under* a fixed map: `merge(var.database_flags,
  local.enforced_flags)`. The judge cited this merge order for *Anti-patterns* 2 in every
  attempt.
- **Identity-first access.** Cloud SQL users are IAM-only, with conditioned
  `cloudsql.instanceUser` grants (E3, E5, E6 and E7 in 3/3), so no password variable
  exists. *Sensitive values* scored 2 in 9/9 attempts. App Service pulls images with a
  managed identity (E4, 3/3).
- **S3 hygiene.** In every attempt:
  - bucket-owner-enforced ownership;
  - cleanup of incomplete multipart uploads;
  - a TLS-only bucket policy;
  - the regional domain output;
  - ready-made consumer IAM policies.
- **Cross-input preconditions:** S3 transitions must come before expiry; Cloud SQL edition
  must be compatible with tier; App Service scale-in must stay below scale-out.

## Weaknesses

- **App Service H2 (security finding, 2/3).** `ftp_publish_basic_authentication_enabled`
  and `webdeploy_publish_basic_authentication_enabled` are absent on the app and the slot,
  so both stay at the provider default (on). The attempt that sets them instead takes
  `minimum_tls_version` as an input, which loses `H3`.
- **Provider pinning.**
  - `B1` lost in 6/9 attempts, including unbounded `>=` on S3.
  - No `provider "aws"` block on S3 in 3/3 attempts (`H15`).
- **Cloud SQL drops databases removed from the input** (`H11`, 3/3). Backups and
  point-in-time recovery cannot be turned off.
- **S3 access logging that cannot deliver** (`H13`, 3/3).

## Characteristic patterns

- **The same four files every time:** `main.tf`, `variables.tf`, `outputs.tf` and
  `versions.tf`, in 8/9 attempts. The judge gave *File layout* 1 in 5/9 for a 200–400-line
  `main.tf`.
- **Input counts sit just at each fixture's budget ceiling,** not well under it.
- **Plenty of validation, unevenly precise.** For example, a `sku_name` pattern that
  rejects valid SKUs such as P0v3, in 3/3 App Service attempts.

{{EXCERPT}}

## Notes on the judge

The judge gave the two App Service attempts with the security finding *Anti-patterns* 2,
citing their hardcoded HTTPS and TLS settings. The judge reads source, and a provider default
that the source never mentions does not appear in it. The rubric's plan-based check is what
catches this class of defect.
