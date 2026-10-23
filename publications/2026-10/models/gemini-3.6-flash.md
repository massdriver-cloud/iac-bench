---
title: "Gemini 3.6 Flash — iac-bench 2026-10"
release: "2026-10"
---

# Gemini 3.6 Flash

| | |
|---|---|
| Developer | Google |
| API identifier | `gemini-3.6-flash` |
| Access | Gemini API |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 0.75 / 3.75 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **54.3** (95% CI 40.0–61.5) |
| Rank | 10 of 10 (95% rank interval 10–10) |
| Mechanical only / judge only | 50.9 (rank 10) / 62.3 (rank 10) |
| Failed gates · insecure attempts | 1/9 · 8/9 |
| Estimated cost, all 9 attempts | $3.14 |

## Summary

Gemini 3.6 Flash places last, with security findings in 8 of 9 attempts and one failed
gate. Its defining habit is to ship secure values as *defaults on consumer-facing inputs*
rather than as fixed properties. The S3 public access block, Cloud SQL public IP and
`ssl_mode`, and App Service HTTPS are all inputs, each with a safe default and no
validation.

That one habit drives most of its losses:

- `H1` lost in every attempt that planned (8/8);
- the interface budget lost in every attempt that planned (8/8);
- *Anti-patterns* 0 in 8/9.

Its resource mechanics, by contrast, are consistently sound.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 62.8 (55.9–65.1) | 0.581 | 4/7 | 73.7 | 0/3 | 3/3 (`H1`) | 22 | 18,077 | 235 s | $0.164 |
| G002 · Cloud SQL | 49.2 (48.2–59.2) | 0.454 | 6/9 | 55.3 | 0/3 | 3/3 (`H1`, `H2`) | 33 | 28,188 | 238 s | $0.297 |
| G003 · App Service | 51.0 (15.0–62.4) | 0.472 | 3/5 | 57.9 | 1/3 | 2/3 (`H1`, `H2`) | 40 | 51,324 | 666 s | $0.473 |

Rubric items not at full credit, counted over attempts that planned: G001: `A3` 3/3, `A5` 3/3, `B1` 1/3, `H1` 3/3, `H9` 1/3, `H12` 3/3, `H13` 3/3, `H15` 2/3; G002: `A8` 3/3, `B1` 2/3, `H1` 3/3, `H2` 3/3, `H4` 1/3, `H5` 1/3, `H7` 3/3, `H9` 3/3, `H10` 3/3, `H11` 3/3; G003: `A6` 2/2, `A7` 2/2, `H1` 2/2, `H2` 2/2, `H3` 1/2, `H4` 1/2, 1 attempt failed the gate. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **Resource mechanics.** *Inline vs separate resources*, *Iteration*, *Lifecycle
  meta-arguments* and *Deprecated patterns* all scored 2 in 9/9 attempts.
- **S3 hygiene,** in 3/3 attempts:
  - bucket-owner-enforced ownership;
  - a 7-day multipart abort;
  - a TLS-deny policy;
  - the regional domain output;
  - unconditional encryption.
- **Identity on Cloud SQL.** IAM authentication, workload service-account logins, managed
  databases and users, and Query Insights in 3/3 attempts.
- **Operational scope on App Service.** The planned attempts include autoscale, a staging
  slot, Application Insights and diagnostics. One adds four metric alerts.

## Weaknesses

- **S3 `H1`, 3/3.** The public access block is fed by inputs: one boolean, or all four
  flags separately.
- **Cloud SQL `H1` and `H2`, 3/3.**
  - `ipv4_enabled` is an input.
  - `ssl_mode` is an unvalidated string, and its own description lists the unencrypted mode
    (excerpt below).
  - Two attempts also let `database_flags` turn IAM authentication off.
- **App Service `H1`/`H2`, in both attempts that planned.** `https_only` is missing on the
  slot or exposed as an input, and the basic-auth publishing flags are never set.
- **Raw passwords as plain, non-sensitive inputs on Cloud SQL** (`H7`, `H10`, 3/3).
- **Failed gate (App Service, 1/3).** The outputs reference a slot resource that the module
  never declares. Five alert variables drive nothing. The judge described this as the
  signature of resources deleted to make an error go away.
- **Almost no validation.** Three `validation` blocks across all nine modules.

## Characteristic patterns

- **The largest interfaces in the field:** 22, 33 and 40 median inputs. The judge never
  gave *Interface design* a 2.
- **"Create or pass an ID" switches** on App Service for the resource group, plan,
  workspace and Application Insights.
- **Scratch files left behind** in 4/9 attempts. One Cloud SQL attempt left 13 empty
  `test*.tf` files.

## Representative excerpt

`G002/gemini-3.6-flash-e1/variables.tf` lines 65–75

```hcl
variable "ipv4_enabled" {
  description = "Whether public IPv4 is assigned to the instance. Default is false (Private IP only)."
  type        = bool
  default     = false
}

variable "ssl_mode" {
  description = "SSL/TLS connection mode: ENCRYPTED_ONLY, TRUSTED_CLIENT_CERTIFICATE_REQUIRED, or ALLOW_UNENCRYPTED_AND_ENCRYPTED."
  type        = string
  default     = "ENCRYPTED_ONLY"
}
```

Both defaults are secure, but each control is an unvalidated consumer input, and the description advertises the unencrypted mode. This fails both mandatory Cloud SQL items.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
