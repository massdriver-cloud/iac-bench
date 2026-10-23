---
title: "Claude Haiku 5.5 — iac-bench 2026-10"
release: "2026-10"
---

# Claude Haiku 5.5

| | |
|---|---|
| Developer | Anthropic |
| API identifier | `claude-haiku-5-5` |
| Access | Anthropic API |
| Weights | Closed |
| List price (USD / M tokens, in / out) | 0.10 / 0.50 (OpenRouter, 2026-10-23) |
| Evaluated | 2026-10-22 (generation) · 2026-10-23 (judge) |
| Attempts | 9 (3 fixtures × 3 samples) |
| **Overall composite** | **66.8** (95% CI 66.1–90.6) |
| Rank | 9 of 10 (95% rank interval 1–9) |
| Mechanical only / judge only | 57.5 (rank 9) / 91.2 (rank 4) |
| Failed gates · insecure attempts | 2/9 · 1/9 |
| Estimated cost, all 9 attempts | $0.11 |

## Summary

Claude Haiku 5.5's overall rank is driven by one fixture. On S3 (G001) its median of 88
ties Claude Opus 5.5 for the best in the field, and on App Service it is mid-field. On
Cloud SQL, two of its three modules failed the gate. Its rank interval (1–9) is the widest
in the release, because one more good Cloud SQL attempt would have put it in the top group.

Both failures share one cause. The module looks up the environment's network inside a
required `project_id`, and the model's own example inputs set that project ID to a
placeholder. `tofu_plan` failed, the model saw the error, and it submitted anyway, saying
so in its summary. The third attempt avoided the lookup and scored 0.929.

It is among the cheapest models in the release, at about 1–2 cents per attempt.

## Scores

| Fixture | Composite median (range) | Rubric median | Expertise | Judge median | ✗ gate | ⚠ security | Median inputs | Median output tokens | Median time | Median cost |
|---|---|---|---|---|---|---|---|---|---|---|
| G001 · S3 | 87.8 (87.2–90.2) | 0.860 | 5/7 | 100.0 | 0/3 | 0/3 | 8 | 9,297 | 102 s | $0.006 |
| G002 · Cloud SQL | 26.8 (25.3–91.0) | 0.000 | 7/9 | 89.5 | 2/3 | 0/3 | 22 | 17,089 | 84 s | $0.011 |
| G003 · App Service | 85.7 (85.2–93.0) | 0.922 | 2/5 | 84.2 | 0/3 | 1/3 (`H2`) | 22 | 21,616 | 367 s | $0.017 |

Rubric items not at full credit, counted over attempts that planned: G001: `A5` 1/3, `H9` 3/3, `H12` 2/3, `H13` 3/3, `H14` 2/3, `H15` 1/3; G002: `H4` 1/1, `H5` 1/1, `H11` 1/1, 2 attempts failed the gate; G003: `A7` 2/3, `H2` 1/3, `H6` 1/3. Definitions are in [Scoring criteria](../scoring-criteria.md).

## Strengths

- **Hardcoded security baseline on every fixture.** S3 public access block and a TLS-only
  policy; Cloud SQL private IP and `ENCRYPTED_ONLY`; App Service HTTPS and transport
  settings.
- **Concept-level inputs.** On S3 an `asset_class` enum drives lifecycle through a map of
  defaults. The judge scored *Interface design* and *Internal logic* 2 in 3/3 S3
  attempts.
- **Locked audit and identity on Cloud SQL.** A locked flag set (IAM authentication,
  connection logging, pgaudit) is merged last or protected by a precondition. Workload
  service-account users are created in 3/3 attempts.
- **Unprompted S3 expertise:** ownership controls, multipart cleanup, TLS enforcement, the
  regional domain output, and deterministic name uniqueness, all in 3/3.

## Weaknesses

- **Failed gates on Cloud SQL (2/3).** It submitted after an observed plan failure (see
  the summary). The prompt requires `minimal.tfvars` to plan cleanly, and credentials come
  from the environment.
- **App Service `H2` (security finding, 1/3).** One attempt sets
  `ftp_publish_basic_authentication_enabled = false` but omits the Web Deploy flag, which
  stays at the provider default (on).
- **Inaccurate descriptions.** *Documentation* median 0 in 5/9 attempts. For example,
  it describes an age-based S3 transition as access-based.
- **Validation stricter than the platform.** Examples:
  - a 7-day cap on transaction-log retention, where Enterprise Plus allows 35;
  - a database-name pattern that rejects hyphens;
  - an image check that rejects digest references.

## Characteristic patterns

- **Validation everywhere, including preconditions across inputs.** For example, prod
  requires REGIONAL, and the network must match the environment.
- **Identity handling varies by attempt.** Cloud SQL is IAM-only in two attempts. Another
  generates a break-glass password into state, and one App Service attempt takes a raw
  registry password.
- **It never builds infrastructure the brief didn't ask for.**

## Representative excerpt

`G002/claude-haiku-5-5-e1/main.tf` lines 4–7

```hcl
data "google_compute_network" "apps" {
  name    = local.network_name
  project = coalesce(var.network_project_id, var.project_id)
}
```

`G002/claude-haiku-5-5-e1/minimal.tfvars` lines 1–4

```hcl
project_id    = "example-dbops-project"
region        = "europe-west1"
environment   = "dev"
instance_name = "orders-dev-pg"
```

A reasonable network lookup, which the reference module also uses, made unplannable by a required `project_id` that the model filled with a placeholder.


---

[Results](../index.md) · [Methodology](../methodology.md) · [Scoring criteria](../scoring-criteria.md)
