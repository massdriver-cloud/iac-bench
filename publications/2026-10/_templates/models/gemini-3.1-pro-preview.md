# Gemini 3.1 Pro

{{FACTS}}

## Summary

Gemini 3.1 Pro writes the leanest modules among the full-size models: few inputs, short
files, low token use. All 9 of its modules planned. Five of the 9 had security findings,
all from settings left unset rather than settings exposed as inputs:

- App Service (3/3): `https_only` and the basic-auth publishing flags are never set, so
  the provider defaults leave HTTP and shared-credential publishing open.
- Cloud SQL (2/3): `ssl_mode` is never set, so unencrypted connections are accepted.

It is also the only model with no `validation` block in any of its nine modules.

{{SCORES}}

## Strengths

- **Hardcoded S3 baseline (3/3).** All four public-access-block settings, unconditional
  encryption, and bucket-owner-enforced ownership.
- **No knobs for network exposure or IAM on Cloud SQL.** `ipv4_enabled = false` is a
  literal, and the IAM authentication flag is merged after consumer flags so it cannot be
  overridden.
- **No credentials taken as input.** IAM users only on Cloud SQL, with the
  service-account suffix stripped correctly.
- **Restraint.** No restraint item lost on any fixture, and the smallest App Service
  interface in the field (median 11 inputs).
- **Low cost and token use.** About 4.7–7.7k output tokens per attempt.

## Weaknesses

- **App Service `H1` and `H2` (security findings, 3/3).** HTTPS-only and the basic-auth
  publishing flags are absent on the web app and the slot (excerpt below).
- **Cloud SQL `H2` (security finding, 2/3).** `ip_configuration` omits `ssl_mode`. The
  third attempt hardcodes it correctly.
- **No input validation (9/9).** *Variables and validation* scored 0 in every attempt.
  The judge named realistic breakages, such as zone balancing turned on by default for a
  plan size that doesn't support it.
- **Domain gaps:**
  - no Cloud SQL login-role grant (E6), connection logging (E8) or Query Insights (E9),
    all 0/3;
  - no tags input on App Service (`H8`, 0/3);
  - no S3 access logging (`H9`, `H13`).

## Characteristic patterns

- **Pass-through inputs.** Variables map one to one onto resource attributes
  (`sku_name`, `disk_type`, `availability_type`). *Interface design* scored 1 in 7/9.
- **Almost no locals.** App Service slot and app blocks are duplicated verbatim.
- **Minimal documentation.** No README in any attempt. Every variable has a description,
  but one description is inverted ("whether or not to allow Terraform to destroy the
  instance" on a deletion-protection input).
- **It under-builds rather than over-builds.** Missing items dominate its losses.

{{EXCERPT}}

## Notes on the judge

Insecure configuration is scored by the rubric, not the judge, so the security findings
move this model's judge grade very little. On Cloud SQL, the attempt with a security
finding received the highest judge grade of the three, and the secure attempt the lowest.
The composite takes both into account. Read either component alone and you get a
misleading picture.
