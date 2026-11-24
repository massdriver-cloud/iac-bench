# Standard Cloud SQL PostgreSQL Module

Reusable OpenTofu root module for provisioning standardized Cloud SQL for PostgreSQL instances across `dev`, `staging`, and `prod`.

## Design Philosophy

### Enforced Everywhere (Non-Negotiable Platform Standards)
- **Private VPC Networking Only**: Public IPv4 is disabled (`ipv4_enabled = false`). Each instance attaches via Private Services Access to the environment VPC (`apps-dev`, `apps-staging`, or `apps-prod`) in the configured Google Cloud project, with private path enabled for Google Cloud services.
- **TLS Required**: `ssl_mode = "ENCRYPTED_ONLY"` on the primary instance and all read replicas.
- **Google Identity Authentication**: `cloudsql.iam_authentication = "on"` is enforced. Engineers (`CLOUD_IAM_USER`), GKE/GCE workloads (`CLOUD_IAM_SERVICE_ACCOUNT`), and Google Groups (`CLOUD_IAM_GROUP`) authenticate via Google identities and receive instance-scoped `roles/cloudsql.instanceUser` and `roles/cloudsql.client` bindings.
- **Security & Access Auditing**: `cloudsql.enable_pgaudit = "on"`, `pgaudit.log` (default `"ddl,role"`), `log_connections = "on"`, `log_disconnections = "on"`, `log_checkpoints = "on"`, and `log_lock_waits = "on"` are enforced and cannot be disabled by per-instance flag overrides.
- **Backups, PITR, & Autoresize**: Daily automated backups, Point-in-Time Recovery (PITR), and automatic disk expansion (`disk_autoresize = true`) are always enabled.
- **Query Insights**: Query Insights with application tags and client addresses is enabled on all primary and replica instances.
- **Consistent Naming, Maintenance, & Labeling**: Instances are named `<name>-<environment>` (read replicas `<name>-<environment>-rr-<key>`), patched during a standardized Sunday 03:00 UTC maintenance window, and labeled consistently.

### DBA-Owned Decisions
- **Required**: `name`, `environment` (`dev` | `staging` | `prod`), and `tier`.
- **Engine & Compute**: `database_version` (default `POSTGRES_16`), `edition` (`ENTERPRISE` | `ENTERPRISE_PLUS`), `region`, `zone`, `secondary_zone`, `availability_type` (defaults to `REGIONAL` in `prod`, `ZONAL` in `dev`/`staging`).
- **Storage & Protection**: `disk_type`, `disk_size`, `disk_autoresize_limit`, `deletion_protection` (defaults to `true` in `staging`/`prod`, `false` in `dev`), `kms_key_name`.
- **Databases, Flags, & Replicas**: `databases`, `database_flags` (merged before mandatory security/audit flags), `pgaudit_log`, `read_replicas`.
- **Access & Backup Tuning**: `iam_users`, `iam_service_accounts`, `iam_groups`, `backup_start_time`, `backup_retention_count`, `pitr_retention_days`, `maintenance_window`.

## Minimal Usage

```hcl
# minimal.tfvars
name        = "example"
environment = "dev"
tier        = "db-custom-2-8192"
```

```sh
tofu plan -var-file=minimal.tfvars
```
