---
title: "Gemini 3.1 Pro: iac-bench 2026-10"
release: "2026-10"
---

# Gemini 3.1 Pro

| | |
|---|---|
| Developer | Google |
| API identifier | `gemini-3.1-pro-preview` |
| Access | Gemini API |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 2.00 / 12.00 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **73.0** (95% CI 69.2–76.2) |
| Rank | 7 of 10 (95% rank interval 6–9) |
| Mechanical only / judge only | 71.9 (rank 7) / 71.9 (rank 8) |
| Failed gates · insecure attempts | 0/9 · 5/9 |
| Estimated cost, all 9 attempts | $2.26 |

## Summary

Gemini 3.1 Pro writes the leanest modules among the full-size models: few inputs, short
files, low token use. All 9 of its modules planned. Five of the 9 had security findings,
all from settings left unset rather than settings exposed as inputs:

- App Service (3/3): `https_only` and the basic-auth publishing flags are never set, so
  the provider defaults leave HTTP and shared-credential publishing open.
- Cloud SQL (2/3): `ssl_mode` is never set, so unencrypted connections are accepted.

It is also the only model with no `validation` block in any of its nine modules.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 74.2 (73.4–80.1) | 0.733 | 3/7 | 78.9 | 0/3 | 0/3 | 5 | 4,677 | 140 s | $0.171 |
| G002 · Cloud SQL | 79.3 (73.5–82.0) | 0.815 | 3/9 | 76.3 | 0/3 | 2/3 (`H2`) | 18 | 6,768 | 128 s | $0.271 |
| G003 · App Service | 65.4 (59.9–69.4) | 0.722 | 0/5 | 60.5 | 0/3 | 3/3 (`H1`, `H2`) | 11 | 7,736 | 231 s | $0.238 |

Rubric items not at full credit, counted over attempts that planned: G001: `H6` 2/3, `H7` 2/3, `H9` 3/3, `H12` 3/3, `H13` 3/3, `H15` 3/3; G002: `A4` 1/3, `B1` 2/3, `H2` 2/3, `H4` 1/3, `H5` 1/3, `H8` 1/3, `H9` 3/3, `H11` 1/3; G003: `H1` 3/3, `H2` 3/3, `H4` 1/3, `H7` 1/3, `H8` 3/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

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

## Representative excerpt

`G003/gemini-3.1-pro-preview-e1/main.tf` lines 45–58

```hcl
resource "azurerm_linux_web_app" "this" {
  name                = var.app_name
  location            = azurerm_resource_group.this.location
  resource_group_name = azurerm_resource_group.this.name
  service_plan_id     = azurerm_service_plan.this.id

  identity {
    type = "SystemAssigned"
  }

  site_config {
    application_stack {
      docker_image_name   = var.container_image
      docker_registry_url = var.container_registry_url
```

An otherwise complete resource that never sets `https_only` or the basic-auth publishing flags. The same omission appears on all six App Service web apps and slots this model wrote.

## Notes on the judge

Insecure configuration is scored by the rubric, not the judge, so the security findings
move this model's judge grade very little. On Cloud SQL, the attempt with a security
finding received the highest judge grade of the three, and the secure attempt the lowest.
The composite takes both into account. Read either component alone and you get a
misleading picture.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
