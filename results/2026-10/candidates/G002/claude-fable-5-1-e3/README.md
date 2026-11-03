# cloudsql-postgres

Standard Cloud SQL for PostgreSQL module for the DBA team. One instance per
module call, attached by private IP to the `apps-<environment>` VPC.

## What is fixed (same on every instance)

| Concern            | Decision                                                                 |
|--------------------|--------------------------------------------------------------------------|
| Network            | Private IP only on `apps-<environment>`; no public IPv4; TLS required (`ENCRYPTED_ONLY`). |
| Authentication     | `cloudsql.iam_authentication=on`; only IAM users/service accounts are created (no password users). |
| Login IAM          | Listed identities get `cloudsql.instanceUser` + `cloudsql.client`, conditioned on this instance only. |
| Backups            | Daily automated backups + point-in-time recovery, always on.             |
| Auditing           | `log_connections`, `log_disconnections`, `log_checkpoints`, `log_lock_waits`, `log_temp_files=0`. |
| Observability      | Query Insights on, with client address and application tags recorded.   |
| Protection         | Deletion protection (API + OpenTofu); cannot be disabled in prod.         |
| HA                 | prod is always `REGIONAL`; others default to `ZONAL`.                     |
| Disk               | Auto-resize on.                                                           |
| Labels             | `environment`, `managed-by`, `engine` always set.                        |

Attempting to override an enforced flag via `database_flags` fails the plan.

## What the DBA decides

PostgreSQL version, tier/edition, disk size/type/growth cap, HA outside prod,
all other `database_flags`, backup window / location / retention, WAL retention,
maintenance window and update track, CMEK key, connector enforcement, databases
(charset/collation), the identities allowed to log in, extra labels.

## After apply

Database-level privileges (`GRANT ... TO "user@example.com"`) are still
granted by a DBA inside PostgreSQL; the module only makes the identity able to
authenticate to this instance.

## Minimal use

```hcl
project_id  = "my-project"
name        = "orders-dev"
environment = "dev"
region      = "europe-west1"
```

See `example-prod.tfvars` for a fuller prod example.
