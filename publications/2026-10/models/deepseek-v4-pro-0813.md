---
title: "DeepSeek V4 Pro: iac-bench 2026-10"
release: "2026-10"
---

# DeepSeek V4 Pro

| | |
|---|---|
| Developer | DeepSeek |
| API identifier | `deepseek/deepseek-v4-pro-0813` |
| Access | OpenRouter |
| Weights | Open |
| List price (USD / M tokens, in / out) | 0.66 / 1.98 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **69.2** (95% CI 63.2–79.3) |
| Rank | 8 of 10 (95% rank interval 6–9) |
| Mechanical only / judge only | 69.5 (rank 8) / 67.5 (rank 9) |
| Failed gates · insecure attempts | 0/9 · 5/9 |
| Estimated cost, all 9 attempts | $0.88 |

## Summary

DeepSeek V4 Pro is close to the leading group on S3 (G001, median 82) and falls well behind
on Cloud SQL and App Service. All 9 of its modules planned. Five of the 9 had a security
finding, each caused by a security setting exposed as an input or left at an insecure
provider default.

Its most distinctive weakness is documentation that describes behavior the code does not
implement. The judge scored *Documentation* 0 in all six of its Cloud SQL and App Service
attempts.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 82.5 (69.6–82.6) | 0.791 | 4/7 | 84.2 | 0/3 | 1/3 (`H1`) | 8 | 27,086 | 432 s | $0.087 |
| G002 · Cloud SQL | 62.1 (60.9–73.8) | 0.641 | 4/9 | 65.8 | 0/3 | 2/3 (`H1`, `H2`) | 22 | 14,092 | 192 s | $0.097 |
| G003 · App Service | 63.2 (57.8–81.8) | 0.708 | 2/5 | 52.6 | 0/3 | 2/3 (`H1`, `H2`) | 21 | 19,960 | 493 s | $0.102 |

Rubric items not at full credit, counted over attempts that planned: G001: `A5` 1/3, `B1` 2/3, `H1` 1/3, `H9` 2/3, `H12` 3/3, `H13` 3/3, `H15` 1/3; G002: `A2` 1/3, `A3` 2/3, `A8` 1/3, `B1` 3/3, `H1` 2/3, `H2` 1/3, `H5` 1/3, `H6` 1/3, `H9` 3/3, `H11` 2/3; G003: `A4` 1/3, `A6` 1/3, `A7` 2/3, `B1` 1/3, `H1` 1/3, `H2` 2/3, `H3` 1/3, `H6` 1/3, `H7` 1/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **Every module planned** (9/9).
- **S3 baseline coverage.** Bucket-owner-enforced ownership, multipart cleanup and the
  regional domain output in 3/3 attempts, and a TLS-only policy in 2/3. The judge gave one
  S3 attempt *Scope* 2 "without unwarranted extras."
- **Dedicated resources.** *Inline vs separate resources* scored 2 in 8/9 attempts.
- **No password users on Cloud SQL.** Only IAM users are created.
- **One App Service attempt meets every core and mandatory item** (rubric 0.944). The model
  knows the settings, but applies them inconsistently.

## Weaknesses

- **Security findings (5/9):**
  - S3, one attempt: all four public-access-block settings are fed by
    `var.block_public_access` (`H1`).
  - Cloud SQL, two attempts: `ipv4_enabled` is an input. In one it defaults to `true`, so
    the defaults plan has a public IP, while the description says "Private-only
    regardless of this flag" (`H1`). In the other, `require_ssl = false` maps to
    unencrypted connections (`H1`, `H2`).
  - App Service, two attempts: the basic-auth publishing flags are never set (`H2`). One
    attempt also makes `https_only` an input (`H1`).
- **Documentation that contradicts the code.** Examples:
  - "least-requests load balancing" that is never configured;
  - a `staging_traffic` input documented to route traffic, which only feeds an output;
  - "0 disables autoresize", which it does not.
- **Lifecycle misuse.** `prevent_destroy = var.deletion_protection` in 3/3 Cloud SQL
  attempts, duplicating the native `deletion_protection` attribute. *Lifecycle
  meta-arguments* scored 0 in all three.
- **Inputs declared and never used,** in several attempts (`zone`, `allocated_ip_range`,
  `staging_traffic`, `service_tag`).

## Characteristic patterns

- **The stated posture and the actual interface disagree** (excerpt below).
- **It leans toward too many inputs.** One S3 attempt has 18 inputs, one Cloud SQL attempt
  34. *Interface design* scored 1 in 9/9.
- **Stray files on Azure,** such as `_tmp_prod.tf` and `_full_test.tfvars`, and a pinned
  `azurerm ~> 3.0` with deprecated arguments in one attempt.

## Representative excerpt

`G002/deepseek-v4-pro-0813-e3/main.tf` lines 30–38

```hcl
    ip_configuration {
      ipv4_enabled    = var.ipv4_enabled
      private_network = var.network

      allocated_ip_range = var.private_ip_allocated_range

      # TLS posture on the (opt-in) public path. Private path traffic never
      # leaves the VPC, but SSL is still enforced end-to-end for defense in depth.
      ssl_mode = var.require_ssl ? "TRUSTED_CLIENT_CERTIFICATE_REQUIRED" : "ALLOW_UNENCRYPTED_AND_ENCRYPTED"
```

The comment says SSL is enforced end to end, and the next line lets a caller turn it off. Public IP is also an input.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
