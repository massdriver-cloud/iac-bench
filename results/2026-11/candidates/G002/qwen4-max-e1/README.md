# Standard Cloud SQL PostgreSQL module

The DBA team's single way to stand up Cloud SQL for PostgreSQL. Instances
are created in the provider's project — the same project that owns the
network team's `apps-dev` / `apps-staging` / `apps-prod` VPCs, each of which
already has private services access configured. The module never creates
or modifies networks, and never configures the Google provider.

## What is standardized (not configurable)

Every instance, in every environment, gets:

| Standard | Setting |
|---|---|
| Private connectivity only | `ipv4_enabled = false`, attached to `apps-<environment>`; no public IP, no authorized networks |
| TLS required | `ssl_mode = "ENCRYPTED_ONLY"` |
| Identity-based access | `cloudsql.iam_authentication = on`; only IAM database users are managed — no password-based SQL users, no root password in state |
| Backups + PITR | daily at 02:00 UTC, 14 retained backups, 7 days of WAL |
| Maintenance | Sunday 03:00 UTC, `stable` track |
| Storage | PD-SSD, autoresize on |
| Observability | Query Insights on (app tags + client address recorded) |
| Safety | deletion protection on at both the API and Terraform levels |
| Tagging | `environment`, `component=postgresql`, `managed-by=opentofu` labels |

The tuning variable `database_flags` cannot override the security flag
(variable validation rejects `cloudsql.iam_authentication` keys).

## What the DBAs decide (variables)

Required per instance:

- `environment` — `dev`, `staging` or `prod`; selects the VPC.
- `instance_name`
- `region`
- `tier` — machine sizing.

Optional, with sensible defaults:

- `database_version` (default `POSTGRES_15`, PostgreSQL-only by validation)
- `availability_type` (`ZONAL` default; use `REGIONAL` for HA — recommended
  for production)
- `disk_size_gb` (default 20; disks autoresize and never shrink)
- `databases` — application databases (UTF-8 / en_US.UTF8)
- `iam_database_users` — Google identities (`CLOUD_IAM_USER` or
  `CLOUD_IAM_SERVICE_ACCOUNT`) registered for IAM database authentication.
  Service-account names are trimmed of `.gserviceaccount.com` as Cloud SQL
  requires. In-database privileges (`CREATE ROLE` / `GRANT`) remain a DBA
  task inside PostgreSQL; the module only registers the login identity.
- `database_flags` — workload tuning flags.

## Usage

```hcl
environment       = "prod"
instance_name     = "pg-prod-orders"
region            = "us-central1"
tier              = "db-custom-4-15360"
availability_type = "REGIONAL"
databases         = ["orders"]
iam_database_users = [
  { id = "dba-oncall@example.com",                        type = "CLOUD_IAM_USER" },
  { id = "orders-app@my-project.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
]
```

`minimal.tfvars` is the smallest valid instantiation (only the four
required decisions).

## Deleting an instance

Deletion protection is deliberately fixed on. Decommissioning is a
two-step, reviewed change: first set both protections off in a dedicated
commit, then destroy.
