---
title: "Claude Sonnet 5.5: iac-bench 2026-10"
release: "2026-10"
---

# Claude Sonnet 5.5

| | |
|---|---|
| Developer | Anthropic |
| API identifier | `claude-sonnet-5-5` |
| Access | Anthropic API |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 2.00 / 10.00 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **86.1** (95% CI 84.8–88.2) |
| Rank | 4 of 10 (95% rank interval 2–5) |
| Mechanical only / judge only | 82.5 (rank 4) / 94.7 (rank 3) |
| Failed gates · insecure attempts | 0/9 · 2/9 |
| Estimated cost, all 9 attempts | $1.52 |

## Summary

Claude Sonnet 5.5 is in the top group overall. Its Cloud SQL result (G002) is second only to
GPT-6 Astra's, by under one point. It is the cheapest model in that group, at roughly a tenth of the
per-attempt cost of Claude Fable 5.1. All 9 attempts planned.

Its two security findings come from a single omission on App Service: in 2 of 3 attempts it
never sets the two basic-auth publishing flags, which the Azure provider enables by default.
The same blocks set HTTPS-only, TLS 1.2 and FTPS-off correctly.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 84.8 (82.5–84.9) | 0.814 | 5/7 | 94.7 | 0/3 | 0/3 | 10 | 8,230 | 161 s | $0.117 |
| G002 · Cloud SQL | 90.6 (89.2–93.1) | 0.875 | 8/9 | 100.0 | 0/3 | 0/3 | 26 | 8,383 | 90 s | $0.114 |
| G003 · App Service | 82.8 (81.6–86.6) | 0.800 | 4/5 | 89.5 | 0/3 | 2/3 (`H2`) | 27 | 13,803 | 362 s | $0.213 |

Rubric items not at full credit, counted over attempts that planned: G001: `A5` 2/3, `B1` 3/3, `H9` 1/3, `H12` 3/3, `H13` 3/3, `H15` 3/3; G002: `A8` 2/3, `B1` 2/3, `H4` 3/3, `H5` 3/3, `H11` 3/3; G003: `A7` 3/3, `B1` 1/3, `H2` 2/3, `H3` 1/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

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

## Representative excerpt

`G003/claude-sonnet-5-5-e1/main.tf` lines 119–133

```hcl
  service_plan_id         = azurerm_service_plan.this.id
  https_only              = true
  client_affinity_enabled = false
  app_settings            = local.app_settings
  tags                    = local.tags

  identity {
    type = "SystemAssigned"
  }

  site_config {
    always_on                               = true
    http2_enabled                           = true
    ftps_state                              = "Disabled"
    minimum_tls_version                     = "1.2"
```

HTTPS, FTPS-off and TLS 1.2 are hardcoded, but neither basic-auth publishing flag is set. Both stay at the provider default (on). This is the cause of the `H2` finding.

## Notes on the judge

The judge gave the two App Service attempts with the security finding *Anti-patterns* 2,
citing their hardcoded HTTPS and TLS settings. The judge reads source, and a provider default
that the source never mentions does not appear in it. The rubric's plan-based check is what
catches this class of defect.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
