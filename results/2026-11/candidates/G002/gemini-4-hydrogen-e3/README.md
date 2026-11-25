# Standard Cloud SQL PostgreSQL Module

Reusable OpenTofu root module for provisioning standardized, private-IP Cloud SQL for PostgreSQL instances with enforced Google Identity IAM authentication and audit logging.

## What Is Standardized Everywhere

Every instance provisioned by this module automatically enforces:

- **Private VPC Networking Only**: Public IPv4 is disabled (`ipv4_enabled = false`). Instances attach via private services access to the environment VPC (`apps-dev`, `apps-staging`, or `apps-prod`) in the configured Google Cloud project.
- **TLS Encryption Enforced**: `ssl_mode = "ENCRYPTED_ONLY"`.
- **Google Identity Authentication & Auditing**:
  - `cloudsql.iam_authentication = "on"` (no static shared password accounts managed by this module)
  - `cloudsql.enable_pgaudit = "on"` (with configurable `pgaudit.log`, defaulting to `ddl,role`)
  - `log_connections = "on"`, `log_disconnections = "on"`, `log_checkpoints = "on"`, `log_lock_waits = "on"`, `log_temp_files = "0"`
  - Conditional project IAM bindings (`roles/cloudsql.instanceUser`, `roles/cloudsql.client`) scoped to the specific instance (and its read replicas) when `manage_iam_bindings = true`.
- **Automated Backups & PITR**: Daily automated backups (`03:00` UTC default) with point-in-time recovery enabled.
- **Query Insights**: Enabled everywhere with application tag and client address recording.
- **Storage Autoresize**: Enabled by default (`disk_autoresize = true`).
- **Standardized Naming & Labels**: Instances are named `<name>-<environment>` and labeled with `environment`, `managed_by = "opentofu"`, and `database_engine = "postgresql"`.

## Environment Defaults

| Setting | `dev` | `staging` | `prod` |
| --- | --- | --- | --- |
| VPC Network | `apps-dev` | `apps-staging` | `apps-prod` |
| Default Tier | `db-custom-1-3840` | `db-custom-1-3840` | `db-custom-2-8192` |
| Availability Type | `ZONAL` | `ZONAL` | `REGIONAL` |
| Initial Disk Size | `20` GB | `20` GB | `100` GB |
| Retained Backups | `7` | `7` | `14` |
| Deletion Protection | `false` | `true` | `true` |
| Maintenance Track | `canary` | `stable` | `stable` |

## What DBAs Own Per Instance

- `name`, `environment`, `region` (and optional `zone` / `secondary_zone`)
- `database_version` (`POSTGRES_13`–`POSTGRES_17`, default `POSTGRES_16`)
- `edition` (`ENTERPRISE` or `ENTERPRISE_PLUS`), `tier`, `availability_type`
- `disk_size`, `disk_type`, `disk_autoresize`, `disk_autoresize_limit`
- `database_flags` (custom PostgreSQL tuning flags merged with enforced security/audit baseline) and `pgaudit_log`
- `databases` (application databases with charset/collation)
- `iam_users`, `iam_service_accounts`, `iam_groups`
- `read_replicas` (optional read replicas inheriting private networking, SSL, IAM auth, insights, and audit logging)
- Backup & maintenance schedule overrides, CMEK (`cmek_key_name`), and `data_cache_enabled`
