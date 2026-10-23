---
title: "GPT-6 Astra — iac-bench 2026-10"
release: "2026-10"
---

# GPT-6 Astra

| | |
|---|---|
| Developer | OpenAI |
| API identifier | `gpt-6-astra` |
| Access | OpenAI API (Responses) |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 10.00 / 50.00 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **86.7** (95% CI 86.0–89.8) |
| Rank | 3 of 10 (95% rank interval 1–5) |
| Mechanical only / judge only | 83.2 (rank 3) / 94.7 (rank 2) |
| Failed gates · insecure attempts | 0/9 · 0/9 |
| Estimated cost, all 9 attempts | $7.26 |

## Summary

GPT-6 Astra has the highest median composite on App Service (G003) and on Cloud SQL (G002),
where it is narrowly ahead of Claude Sonnet 5.5. It falls into the lower half of the field on S3 (G001). The spread
across fixtures is the widest of any model in the top group, and it comes from a single
design stance rather than from errors. On S3 it builds a bucket that never deletes anything
and offers no retention controls. The rubric treats that as missing data-hygiene items. The
judge reads the same module as restrained and free of gold-plating.

All 9 attempts planned. No security setting is exposed as an input in any of them. The one
security finding initially recorded was a scorer defect, corrected before publication (see
[Methodology §7](../methodology.md#7-errata-and-re-scoring)).

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 72.8 (72.0–79.6) | 0.640 | 4/7 | 94.7 | 0/3 | 0/3 | 4 | 4,361 | 189 s | $0.318 |
| G002 · Cloud SQL | 91.3 (89.9–93.9) | 0.908 | 5/9 | 100.0 | 0/3 | 0/3 | 19 | 6,411 | 158 s | $0.447 |
| G003 · App Service | 95.9 (95.2–98.3) | 1.000 | 4/5 | 89.5 | 0/3 | 0/3 | 19 | 21,718 | 561 s | $1.802 |

Rubric items not at full credit, counted over attempts that planned: G001: `B1` 2/3, `H6` 3/3, `H7` 3/3, `H9` 3/3, `H12` 3/3, `H13` 3/3, `H14` 3/3, `H15` 2/3; G002: `B1` 2/3, `H4` 3/3, `H5` 3/3, `H11` 2/3; G003: `A7` 1/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **Security posture fixed in code in all 9 modules.** On Cloud SQL this adds
  `connector_enforcement = "REQUIRED"`, and validation rejects any attempt to override IAM
  authentication. On App Service, HTTPS-only and disabled basic-auth publishing are set on
  both the app and the slot.
- **IAM grants scoped to one instance.** On Cloud SQL it grants `cloudsql.client` and
  `cloudsql.instanceUser` with an IAM condition on the instance name, in 3/3 attempts. This
  closes a cross-instance access path that the rubric does not test (excerpt below).
- **Interfaces sized to the audience:** 4–6 inputs for S3 novices, 15–20 for DBAs, 19–21
  for SREs. The fewest inputs of any model with comparable coverage.
- **Validation that teaches.** The judge gave *Variables and validation* 2 in every S3
  reading.
- **Restraint.** *Scope* 2 in 27 of 27 judge readings.

## Weaknesses

- **S3 has no retention controls (3/3).** It has:
  - no expiration or transition rules (`H6`);
  - no noncurrent-version handling (`H7`), so with versioning on, old versions accumulate
    without limit;
  - no access logging (`H9`, `H13`);
  - no way to set `force_destroy` (`H14`).

  Together these cost 21 of the fixture's 86 weight points. A code comment gives the
  reason: the module "cannot know the application's retention requirements."
- **Provider constraints that admit a new major:** `>= 5.0, < 7.0` and `>= 6.0, < 8.0` in
  4 of 9 attempts (`B1`).
- **Backups and point-in-time recovery cannot be turned off** on Cloud SQL (`H4`/`H5` at
  0.75 in 3/3).
- **Duplicate inputs on App Service.** Every attempt takes the registry both as a login URL
  and as an ACR resource ID, though the URL can be looked up from the ID. The judge marked
  this down under *Data sources vs inputs* in 8 of 9 readings.

## Characteristic patterns

- **Object-typed inputs with `optional()` defaults** (`capacity`, `staging`, `registry`),
  checked with preconditions.
- **Long READMEs** (62–100 lines), even for a 4-input S3 module. The judge called one of
  them noise.
- **The full operating stack on App Service.** Every attempt builds its own resource group,
  Log Analytics, Application Insights, an action group and metric alerts.

## Representative excerpt

`G002/gpt-6-astra-e3/main.tf` lines 102–116

```hcl
# Additive grants, not authoritative policies. Conditions prevent this module's
# grants from allowing connection/login to other instances in the project.
resource "google_project_iam_member" "database_access" {
  for_each = local.iam_grants

  project = var.project_id
  member  = each.value.member
  role    = each.value.role

  condition {
    title       = "cloudsql-${var.instance_name}"
    description = "Connection and IAM database login to ${var.instance_name} only"
    expression  = "resource.name == 'projects/${var.project_id}/instances/${google_sql_database_instance.postgres.name}' && resource.service == 'sqladmin.googleapis.com'"
  }
}
```

Project-level Cloud SQL roles granted with an IAM condition on this one instance. Without the condition, the same grant would allow login to every instance in the project.

## Notes on the judge

The S3 fixture shows the largest gap between the two components for this model:
mechanical about 64 against a judge grade of 94.7. The doctrine the judge applies does not
require retention controls on a general-purpose bucket. The rubric does, because the brief
names logs and generated files, data that accumulates.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
