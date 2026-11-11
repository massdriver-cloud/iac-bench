# Cloud SQL for PostgreSQL: standard instance module

One instance per root-module instantiation. Plan with:

    tofu plan -var-file=minimal.tfvars

`examples/prod.tfvars` shows a fuller configuration.

## What is the same on every instance (not configurable)

| Area | Setting |
| --- | --- |
| Network | Private IP only, on `apps-<environment>`. No public address, no authorised networks. |
| Encryption in transit | `ssl_mode = ENCRYPTED_ONLY`. |
| Authentication | IAM database authentication on. The module creates no password users. |
| Audit | Connections and disconnections logged; pgAudit enabled at instance level. |
| Backups | Daily backups and point-in-time recovery always on. |
| Storage | SSD, auto-grow on. |
| Observability | Query Insights on, with application tags and client addresses. |
| Maintenance track | `canary` in dev and staging, `stable` in prod, so prod gets releases last. |
| Naming and labels | Instance is `<name>-<environment>`; labelled `environment`, `service`, `managed-by`. |
| Databases | UTF8 / `en_US.UTF8`. Removing one from `databases` never drops it. |

## What DBAs decide

Required: `project_id`, `name`, `environment`, `region`, `database_version`.

Optional: `edition`, `tier`, `disk_size_gb`, `disk_autoresize_limit_gb`,
`high_availability`, `zone`, `databases`, `database_flags`, `iam_groups`,
`iam_users`, `iam_service_accounts`, `backup_start_time`,
`backup_retention_count`, `transaction_log_retention_days`, `backup_location`,
`maintenance_window`, `deletion_protection`, `kms_key_name`, `labels`,
`network_project_id`, `allocated_ip_range`.

Defaults that depend on the environment:

| | dev / staging | prod |
| --- | --- | --- |
| High availability | off | on |
| Backups kept | 7 | 30 |
| Backups retained and final backup taken on instance deletion | no | yes (30 days) |

## Access

Listing an identity in `iam_groups`, `iam_users` or `iam_service_accounts`
creates the matching Cloud SQL IAM database user and grants
`roles/cloudsql.instanceUser` and `roles/cloudsql.client` on the project,
conditioned to this instance only. Privileges inside PostgreSQL are granted by
the DBAs; a new IAM user starts with none.

## Things the module relies on but does not manage

- The `apps-<environment>` VPC and its private services access connection
  (network team).
- The Cloud SQL Admin API being enabled in the project.
- Data Access audit logs for Cloud SQL at project or organisation level, which
  is where IAM logins and pgAudit records are written.
- `CREATE EXTENSION pgaudit` in each database, which pgAudit needs before it
  records anything.

## Teardown

`deletion_protection` defaults to `true`. To delete an instance, set it to
`false`, apply, then destroy.
