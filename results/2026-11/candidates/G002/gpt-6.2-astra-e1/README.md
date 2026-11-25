# Cloud SQL for PostgreSQL

Use one root state per instance. The Google provider's default project must contain the existing `apps-dev`, `apps-staging`, or `apps-prod` network, with private services access ready. Enable the Compute and Cloud SQL Admin APIs and run with credentials permitted to read the network, use it for Cloud SQL, and manage SQL resources. This root does not change networking, project IAM, or API enablement.

Start with `minimal.tfvars`, choose a unique instance name, and select a region, PostgreSQL version, and tier supported together in the chosen edition. Run `tofu init`, then `tofu plan -var-file=minimal.tfvars`. Review the plan before applying with the same variable file.

The baseline is private IP only, encrypted connections, IAM database authentication, daily backups (14 retained), and seven days of PITR logs. Regional HA and deletion protection are on by default. SSD storage auto-grows; `disk_size_gb` is a creation-time size, intentionally ignored after creation so growth does not cause a replacement plan. See `variables.tf` for sizing, availability, backup window, flag, and database inputs.

## Connecting with an identity

- Add each human email to `iam_users` and each workload's full Google service account email to `iam_service_accounts`. No passwords are generated. Cloud SQL PostgreSQL uses the service account email without `.gserviceaccount.com` as its database username.
- Have the IAM administrator grant those identities `roles/cloudsql.instanceUser` and, for connector access, `roles/cloudsql.client`, scoped to the intended instance where possible. Use GKE Workload Identity or an attached Compute Engine service account rather than distributing service account keys.
- From a client with a network path to the private IP, run Cloud SQL Auth Proxy v2 with `--private-ip --auto-iam-authn` and the `connection_name` output, or configure an equivalent language connector. Connect using the database username corresponding to the connector's credentials.
- IAM logins don't grant application table permissions. Have a database administrator grant the appropriate PostgreSQL roles in each database. Retain separate login identities so grants and audit records can distinguish callers. Review Cloud SQL audit and PostgreSQL logging configuration against the team's event-retention requirements.

For intentional instance removal, first apply with `deletion_protection = false` and review recovery requirements before destroying. Instance protection does not guard individual databases or users removed from their respective input sets.
