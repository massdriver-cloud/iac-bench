---
title: "Kimi K3 — iac-bench 2026-10"
release: "2026-10"
---

# Kimi K3

| | |
|---|---|
| Developer | Moonshot AI |
| API identifier | `moonshotai/kimi-k3` |
| Access | OpenRouter |
| Weights | Open |
| List price (USD / M tokens, in / out) | 0.24 / 11.94 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **82.4** (95% CI 57.3–84.7) |
| Rank | 5 of 10 (95% rank interval 5–9) |
| Mechanical only / judge only | 80.6 (rank 5) / 86.0 (rank 6) |
| Failed gates · insecure attempts | 1/9 · 4/9 |
| Estimated cost, all 9 attempts | $3.96 |

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

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 81.1 (67.5–85.6) | 0.767 | 4/7 | 92.1 | 0/3 | 1/3 (`H1`) | 11 | 21,595 | 317 s | $0.263 |
| G002 · Cloud SQL | 79.2 (78.4–80.0) | 0.793 | 6/9 | 81.6 | 0/3 | 3/3 (`H2`) | 22 | 31,557 | 494 s | $0.409 |
| G003 · App Service | 86.9 (25.3–89.4) | 0.889 | 4/5 | 84.2 | 1/3 | 0/3 | 27 | 48,604 | 853 s | $0.624 |

Rubric items not at full credit, counted over attempts that planned: G001: `A5` 3/3, `B1` 2/3, `H1` 1/3, `H9` 1/3, `H12` 3/3, `H13` 3/3, `H15` 3/3; G002: `B1` 3/3, `H2` 3/3, `H11` 3/3; G003: `A7` 2/2, 1 attempt failed the gate. Definitions are in [Scoring criteria](../scoring-criteria.md).

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

## Representative excerpt

`G002/kimi-k3-e1/variables.tf` lines 200–209

```hcl
variable "ssl_mode" {
  description = "TLS enforcement for connections. The organizational standard is ENCRYPTED_ONLY; TRUSTED_CLIENT_CERTIFICATE_REQUIRED additionally demands mutual TLS. Do not weaken this without a security review."
  type        = string
  default     = "ENCRYPTED_ONLY"

  validation {
    condition     = contains(["ALLOW_UNENCRYPTED_AND_ENCRYPTED", "ENCRYPTED_ONLY", "TRUSTED_CLIENT_CERTIFICATE_REQUIRED"], var.ssl_mode)
    error_message = "ssl_mode must be one of ALLOW_UNENCRYPTED_AND_ENCRYPTED, ENCRYPTED_ONLY or TRUSTED_CLIENT_CERTIFICATE_REQUIRED."
  }
}
```

The description states the standard and warns against weakening it, yet the validation accepts the unencrypted mode. That one list entry cost `H2` in all three Cloud SQL attempts.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
