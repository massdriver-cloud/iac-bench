---
title: "GPT-6 Luna — iac-bench 2026-10"
release: "2026-10"
---

# GPT-6 Luna

| | |
|---|---|
| Developer | OpenAI |
| API identifier | `gpt-6-luna` |
| Access | OpenAI API (Responses) |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 0.10 / 0.50 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **81.5** (95% CI 79.8–82.1) |
| Rank | 6 of 10 (95% rank interval 5–7) |
| Mechanical only / judge only | 79.7 (rank 6) / 84.2 (rank 7) |
| Failed gates · insecure attempts | 0/9 · 0/9 |
| Estimated cost, all 9 attempts | $0.05 |

## Summary

GPT-6 Luna is the small tier of the GPT-6 family. It is one of four models with no
security findings and no failed gates in 9 attempts; the others are Claude Opus 5.5, Claude
Fable 5.1 and GPT-6 Astra. It does this at the lowest cost in the field: well under a cent per
attempt at list prices.

Its score is limited by operational features it leaves out. On S3 there is no lifecycle
and no logging. On Cloud SQL there is no database deletion guard and no login-role grant.
On App Service it uses registry passwords instead of managed-identity image pulls.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 74.3 (71.3–75.1) | 0.674 | 3/7 | 94.7 | 0/3 | 0/3 | 4 | 3,550 | 104 s | $0.003 |
| G002 · Cloud SQL | 84.5 (82.4–84.7) | 0.853 | 5/9 | 84.2 | 0/3 | 0/3 | 16 | 5,377 | 112 s | $0.004 |
| G003 · App Service | 85.7 (85.0–86.7) | 0.958 | 2/5 | 73.7 | 0/3 | 0/3 | 18 | 9,184 | 340 s | $0.007 |

Rubric items not at full credit, counted over attempts that planned: G001: `B1` 3/3, `H6` 3/3, `H7` 3/3, `H9` 3/3, `H12` 3/3, `H13` 3/3, `H14` 2/3, `H15` 2/3; G002: `A5` 1/3, `B1` 3/3, `H4` 3/3, `H5` 3/3, `H9` 1/3, `H11` 3/3; G003: `A7` 1/3, `H7` 2/3, `H9` 1/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **Secure in every attempt.**
  - S3: bucket-owner-enforced ownership, the full public access block and a TLS-deny
    policy.
  - Cloud SQL: private IP only and `ENCRYPTED_ONLY`, with validation that stops callers
    overriding IAM authentication.
  - App Service: HTTPS-only, TLS 1.2, FTPS off and basic-auth publishing off.
- **A small interface for S3's novice audience** (2–5 inputs). The judge noted that the
  module "settles every S3 decision itself."
- **Strong App Service coverage on the rubric.** Rubric median 0.958, second in the field.
- **Speed and cost.** Median output of about 3.5–9k tokens per attempt, and S3 and Cloud
  SQL attempts finish in under two minutes.

## Weaknesses

- **S3 data hygiene and logging missing (3/3):**
  - no lifecycle rules (`H6`, `H7`), although versioning is on;
  - no access logging (`H9`, `H13`);
  - no multipart cleanup (E2).
- **Provider constraints that admit a new major,** on S3 and Cloud SQL in 6/6 attempts
  (`B1`).
- **Cloud SQL gaps:**
  - no `deletion_policy` (`H11`, 3/3);
  - no `cloudsql.instanceUser` grant (E6, 0/3), so the IAM users it creates cannot log
    in;
  - no connection logging (E8), although the brief says access is audited by identity.
- **A latent defect.** In one Cloud SQL attempt the `databases` input fails at plan time
  as soon as any database is declared: a `set(string)` is read as an object. The judge
  caught this (*Internal logic* 0). The rubric did not, because the sweep does not
  populate collection inputs.
- **Registry passwords on App Service (3/3).** It creates a managed identity but still
  routes registry credentials through app settings. *Sensitive values* scored 1 in 3/3
  attempts.

## Characteristic patterns

- **Minimal builds.** It covers what the brief literally asks and adds little: no alerts,
  no Key Vault references, no consumer IAM policies.
- **A flat layout.** Most code sits in `main.tf`. App Service slot configuration is copied
  from the app instead of shared through locals.
- **Validation on most inputs, but rarely across inputs.**

## Representative excerpt

`G003/gpt-6-luna-e1/main.tf` lines 58–63

```hcl
  registry_settings = var.container_registry_username == null ? {} : {
    DOCKER_REGISTRY_SERVER_USERNAME = var.container_registry_username
    DOCKER_REGISTRY_SERVER_PASSWORD = var.container_registry_password
  }

  app_settings = merge(var.app_settings, local.required_app_settings, local.registry_settings)
```

Registry credentials are routed through app settings, although the same module creates a system-assigned managed identity that could pull images instead.

## Notes on the judge

The two components point in opposite directions for this model.

| Fixture | Judge | Rubric |
|---|---|---|
| S3 | High (94.7): rewards the lean, secure interface | Eighth in the field: charges for every missing hygiene item |
| App Service | Below every higher-ranked model: marks down registry passwords and duplicated slot configuration | Second in the field |


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
