# Standard Cloud SQL PostgreSQL module

This root module is the DBA team's opinionated baseline for PostgreSQL on Cloud SQL. It deliberately standardizes security and operability while exposing the decisions that normally differ between databases: capacity, availability, zones, maintenance and backup timing, retention, PostgreSQL flags, databases, and IAM principals.

## Organizational baseline

Every instance has:

- private IP only on the supplied existing VPC; no public IP or authorized networks;
- TLS required with `ssl_mode=ENCRYPTED_ONLY`;
- Cloud SQL IAM database authentication enabled, with no password-based users created;
- automated daily backups, point-in-time recovery, and transaction-log retention;
- storage autoresize (with a configurable safety limit) and SSD storage by default;
- Query Insights, application tags, and client addresses enabled;
- a stable-track maintenance window and standard PostgreSQL connection/checkpoint/lock logging;
- deletion protection in both Cloud SQL and OpenTofu;
- `component=postgresql` and `managed-by=opentofu` labels.

DBAs can override the operational logging flags through `database_flags`, but the module always forces `cloudsql.iam_authentication=on`. No flag can re-enable public connectivity or disable TLS.

## Prerequisites

1. The Cloud SQL Admin API is enabled in the instance project and the caller can manage Cloud SQL instances, databases, and users.
2. The network team has created the target custom VPC and configured **private services access** on it. This module intentionally does not create or modify VPCs, allocated ranges, peering, firewall rules, or DNS. Pass the full or relative network self link, for example `projects/my-project/global/networks/apps-prod`.
3. If `encryption_key_name` is set, the project's Cloud SQL service agent already has permission to use that Cloud KMS key.
4. Each IAM principal has the Google Cloud IAM permissions needed to connect. At minimum this normally includes `roles/cloudsql.instanceUser`; clients using a Cloud SQL connector also need the appropriate client permissions (commonly `roles/cloudsql.client`). These project-level grants are deliberately not made by this instance module because they are security-team authorization decisions and can affect other instances.

## Example

```hcl
project_id        = "example-project"
instance_name     = "orders-prod"
region            = "us-central1"
network_self_link = "projects/example-project/global/networks/apps-prod"

edition           = "ENTERPRISE"
database_version  = "POSTGRES_16"
machine_type      = "db-custom-4-16384"
availability_type = "REGIONAL"
disk_size         = 100

# Defaults shown here can be changed without replacing the instance.
disk_autoresize_limit        = 500
backup_start_time            = "03:00"
backup_retained_backups      = 14
transaction_log_retention_days = 7
maintenance_day              = 7
maintenance_hour             = 4

iam_users = {
  "alice@example.com"                                      = "CLOUD_IAM_USER"
  "orders-api@example-project.iam.gserviceaccount.com"    = "CLOUD_IAM_SERVICE_ACCOUNT"
}

databases = {
  orders = {}
}

database_flags = {
  max_connections = "200"
}

labels = {
  environment = "prod"
  application = "orders"
  team        = "dba"
}
```

Use `CLOUD_IAM_USER` for people and `CLOUD_IAM_SERVICE_ACCOUNT` for workloads. The map key is the full Google identity email. Clients authenticate using IAM database authentication, not a PostgreSQL password. Service-account login names have Cloud SQL's documented service-account username format; consult `iam_database_users` and the Cloud SQL IAM authentication documentation when constructing connection configuration.

The managed `postgres` database is left alone. Entries in `databases` create additional application databases only; schemas, tables, PostgreSQL role grants, and extensions remain database-administration concerns and should be managed with an appropriate PostgreSQL provider after instance creation.

## Destroying deliberately

`deletion_protection` defaults to `true`. To retire an instance, first set it to `false` and apply, review the data-retention implications, then run the destroy operation separately. Additional databases otherwise follow their normal OpenTofu resource lifecycle.

## Minimal plan

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

Replace the example project and network with real values before applying. `minimal.tfvars` uses a ZONAL, one-vCPU instance with no additional databases or IAM users; it is the smallest valid configuration, not a production profile.
