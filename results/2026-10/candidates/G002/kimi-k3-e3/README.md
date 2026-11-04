# Cloud SQL for PostgreSQL — team standard module

Every PostgreSQL database the DBA team runs is a Cloud SQL instance stood up
with this module. It exists so that no two instances are configured alike by
accident: the decisions that should be the same everywhere are made here,
once, and the decisions that are genuinely per-instance are the module's
inputs.

## What the module standardises (not re-decidable per instance)

- **Private connectivity only.** No public IP. The instance draws a private IP
  from the environment VPC (`apps-dev` / `apps-staging` / `apps-prod`), where
  the network team has already configured private services access. This module
  attaches to that network; it does not create or manage it.
- **IAM database authentication, always.** `cloudsql.iam_authentication=on` is
  enforced and cannot be overridden via `database_flags`. Database logins are
  created **only** for Google identities (engineers, service accounts, groups)
  — there are no password users, because access is audited by Google identity.
- **Backups + point-in-time recovery** every night (02:00 UTC), 14 retained
  backups, 7 days of transaction logs.
- **High availability by default** (`REGIONAL`), deletion protection on.
- **Maintenance** Sunday 03:00, stable release track.
- **Query Insights on** everywhere (query strings 1024 chars, app tags and
  client addresses recorded).
- **Storage autoresize on**, SSD storage, TLS-encrypted connections only.

## What the DBA team decides per instance (module inputs)

Project, region, instance name and target network have no defaults — supply
them every time. Everything else has a team-standard default and only needs
overriding when an instance genuinely deviates: PostgreSQL version and
edition, machine tier, `ZONAL` vs `REGIONAL`, disk size, database flags,
databases to create (`databases`), IAM logins to grant (`iam_users`), CMEK
key, labels, backup/maintenance tuning.

## Usage

```hcl
module "orders_db" {
  source = "..."

  project_id        = "example-project"
  region            = "europe-west1"
  instance_name     = "pg-orders-prod"
  network_self_link = "projects/example-net-project/global/networks/apps-prod"

  tier          = "db-custom-4-16384"
  database_flags = { "max_connections" = "300" }

  databases = {
    orders = {}
  }

  iam_users = {
    alice  = { email = "alice@example.com" }
    orders = { email = "orders@example-project.iam.gserviceaccount.com",
               type  = "CLOUD_IAM_SERVICE_ACCOUNT" }
  }
}
```

## Notes

- For service-account logins, Cloud SQL drops the `.gserviceaccount.com`
  suffix from the login name; the module handles that for you.
- When using CMEK (`encryption_key_name`), grant the project's Cloud SQL
  service agent (`service-<project-number>@gcp-sa-cloud-sql.iam.gserviceaccount.com`)
  encrypt/decrypt rights on the key before apply.
