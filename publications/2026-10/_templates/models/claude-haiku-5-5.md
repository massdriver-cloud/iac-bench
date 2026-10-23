# Claude Haiku 5.5

{{FACTS}}

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

{{SCORES}}

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

{{EXCERPT}}
