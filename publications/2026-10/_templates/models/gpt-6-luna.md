# GPT-6 Luna

{{FACTS}}

## Summary

GPT-6 Luna is the small tier of the GPT-6 family. It is one of four models with no
security findings and no failed gates in 9 attempts; the others are Claude Opus 5.5, Claude
Fable 5.1 and GPT-6 Astra. It does this at the lowest cost in the field: well under a cent per
attempt at list prices.

Its score is limited by operational features it leaves out. On S3 there is no lifecycle
and no logging. On Cloud SQL there is no database deletion guard and no login-role grant.
On App Service it uses registry passwords instead of managed-identity image pulls.

{{SCORES}}

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

{{EXCERPT}}

## Notes on the judge

The two components point in opposite directions for this model.

| Fixture | Judge | Rubric |
|---|---|---|
| S3 | High (94.7): rewards the lean, secure interface | Eighth in the field: charges for every missing hygiene item |
| App Service | Below every higher-ranked model: marks down registry passwords and duplicated slot configuration | Second in the field |
