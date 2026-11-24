# Standard Cloud SQL PostgreSQL Module

Reusable OpenTofu root module for provisioning and managing standardized Cloud SQL for PostgreSQL instances.

## Design Split: Platform Standards vs. DBA Decisions

### Standardized Everywhere (Enforced by Module)
- **Private VPC Networking Only**: Public IP (`ipv4_enabled`) is always disabled. Instances attach automatically to the environment's pre-peered VPC (`apps-dev`, `apps-staging`, or `apps-prod`) via Private Services Access, with Private Path for Google Cloud Services enabled.
- **TLS Always Enforced**: `ssl_mode` is set to `ENCRYPTED_ONLY` by default (or `TRUSTED_CLIENT_CERTIFICATE_REQUIRED` when `require_client_certificate = true`).
- **IAM-Based Authentication & Instance-Scoped Access**:
  - `cloudsql.iam_authentication = "on"` is always enforced; no static database passwords are created or managed.
  - Engineers (`iam_users`), GKE/GCE workloads (`iam_service_accounts`), and Google Groups (`iam_groups`) receive `google_sql_user` entries (`CLOUD_IAM_USER`, `CLOUD_IAM_SERVICE_ACCOUNT`, `CLOUD_IAM_GROUP`) and `roles/cloudsql.instanceUser` + `roles/cloudsql.client` bindings **scoped with an IAM condition** to this instance and its read replicas.
- **Audit & Connection Logging**: `cloudsql.enable_pgaudit = "on"`, `log_connections = "on"`, `log_disconnections = "on"`, `log_checkpoints = "on"`, and `log_lock_waits = "on"` are always enabled.
- **Backups & Point-in-Time Recovery (PITR)**: Automated daily backups and WAL-based PITR are always enabled, with environment-appropriate minimum retention defaults (`retained_backups >= 7`).
- **Query Insights & Monitoring**: Query Insights (including application tags and client addresses) and baseline Cloud Monitoring alert policies (CPU, memory, disk, availability) are enabled out of the box.
- **Storage & Deletion Safety**: `PD_SSD` with `disk_autoresize = true` and `deletion_protection = true` by default.

### DBA-Owned Inputs (Configurable Per Instance)
- **Identity & Environment**: `name` and `environment` (`dev`, `staging`, `prod`)
- **Engine & Sizing**: `database_version` (`POSTGRES_13`–`POSTGRES_17`), `edition` (`ENTERPRISE` / `ENTERPRISE_PLUS`), `tier`, `availability_type` (`REGIONAL` / `ZONAL`), `disk_size`, `disk_autoresize_limit`
- **Databases & PostgreSQL Tuning**: `databases`, `database_flags` (merged with platform defaults and mandatory audit/IAM flags)
- **Access**: `iam_users`, `iam_service_accounts`, `iam_groups`, `enforce_cloud_sql_connector`, `require_client_certificate`
- **Operations**: `backup_configuration`, `maintenance_window`, `read_replicas`, `alert_notification_channels`, `deletion_protection`, `labels`

## Usage

### Minimal (`minimal.tfvars`)

```hcl
name        = "orders"
environment = "dev"
```

### Production Example

```hcl
name             = "billing"
environment      = "prod"
database_version = "POSTGRES_16"

databases = {
  billing = {}
}

database_flags = {
  max_connections = "500"
  work_mem        = "16384"
  "pgaudit.log"   = "write,ddl,role"
}

iam_service_accounts = [
  "billing-api@my-project.iam.gserviceaccount.com",
]

iam_groups = [
  "dba-team@example.com",
]

read_replicas = {
  analytics = {
    region = "us-east1"
  }
}
```
