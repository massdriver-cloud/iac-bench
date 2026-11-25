# Cloud SQL PostgreSQL Module for DBA Team

Reusable OpenTofu root module for provisioning and managing standardized, production-grade PostgreSQL instances on Google Cloud SQL.

## Architecture & Design Decisions

### 1. Standardization vs DBA Ownership
This module standardizes infrastructure-wide invariants so DBAs do not need to re-decide boilerplate requirements, while retaining full control over workload-specific database parameters:

* **DBA Decisions (Configurable)**:
  - Instance name (`name`)
  - Target environment (`environment`: `dev`, `staging`, `prod`)
  - PostgreSQL version (`database_version`, default: `POSTGRES_16`)
  - Machine tier (`tier`, default: `db-custom-2-7680` - 2 vCPU / 7.5 GB RAM)
  - Storage configuration (`disk_size_gb`, `disk_type`, `disk_autoresize_limit`)
  - Availability & HA override (`availability_type`)
  - Databases to create (`databases`)
  - IAM database users & service accounts (`iam_users`, `iam_service_accounts`)
  - Custom PostgreSQL database flags (`database_flags`, merged with mandatory audit baseline)
  - Read replicas (`read_replicas`)

* **Enforced Standards (Pre-configured)**:
  - **Private Network Only**: Public IP is completely disabled (`ipv4_enabled = false`). All connections route over Private Services Access (PSA) to the VPC networks (`apps-dev`, `apps-staging`, `apps-prod`).
  - **Encryption in Transit**: Enforces SSL/TLS encryption (`ssl_mode = "ENCRYPTED_ONLY"`).
  - **Automated Backups & PITR**: Automated daily backups at 03:00 UTC with Point-in-Time Recovery (WAL archiving enabled) and a 14-backup retention policy.
  - **Storage Resilience**: Automatic disk expansion (`disk_autoresize = true`) on SSD (`PD_SSD`) storage to prevent out-of-disk crashes.
  - **Deletion Protection**: Automatically enabled for `prod` and `staging` to prevent catastrophic data loss.
  - **Query Insights**: Built-in monitoring with client address and application tag recording enabled.
  - **Maintenance Windows**: Scheduled during low-traffic windows (Sundays at 04:00 UTC) on the `stable` update track.

### 2. Networking
Applications running on GKE and Compute Engine communicate across environment-specific VPC networks (`apps-dev`, `apps-staging`, `apps-prod`) using Private Services Access.
- Instances automatically attach to the VPC matching `var.environment` (e.g. `projects/<project>/global/networks/apps-dev`).
- Custom VPCs can also be passed via `var.network`.
- Private path for Google Cloud services is enabled.

### 3. Identity & Auditing
Every engineer and workload has a Google identity. To support security team auditing:
- `cloudsql.iam_authentication = "on"` is enforced by default.
- Engineer accounts are provisioned as `CLOUD_IAM_USER` via `var.iam_users`.
- GKE and Compute Engine workload identities are provisioned as `CLOUD_IAM_SERVICE_ACCOUNT` via `var.iam_service_accounts` (with automatic `.gserviceaccount.com` suffix truncation as required by Cloud SQL PostgreSQL).
- pgAudit (`cloudsql.enable_pgaudit = "on"`, `pgaudit.log = "all"`) and PostgreSQL connection logging (`log_connections`, `log_disconnections`, `log_lock_waits`, `log_temp_files`) are enabled to produce tamper-evident audit trails tied to authenticated Google identities.
- Strong password policy enforcement (`password_validation_policy`).

## Usage

### Minimal Instantiation (`minimal.tfvars`)
```hcl
name = "dba-postgres-instance"
```

### Production Example
```hcl
name                 = "orders-db"
environment          = "prod"
tier                 = "db-custom-4-16384"
disk_size_gb         = 100
databases            = ["orders", "inventory"]
iam_users            = ["alice@company.com", "bob@company.com"]
iam_service_accounts = ["order-svc@company-prod.iam.gserviceaccount.com"]

database_flags = {
  max_connections = "500"
  work_mem        = "64MB"
}
```
