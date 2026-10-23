# GPT-6 Astra

{{FACTS}}

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

{{SCORES}}

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

{{EXCERPT}}

## Notes on the judge

The S3 fixture shows the largest gap between the two components for this model:
mechanical about 64 against a judge grade of 94.7. The doctrine the judge applies does not
require retention controls on a general-purpose bucket. The rubric does, because the brief
names logs and generated files, data that accumulates.
