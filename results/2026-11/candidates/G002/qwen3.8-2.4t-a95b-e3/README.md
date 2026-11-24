# Standard PostgreSQL on Cloud SQL

The DBA team's standard module for standing up PostgreSQL instances on Cloud
SQL. One module, one way to run Postgres: everything that should be identical
across all instances is decided here once; everything that is genuinely a
per-database decision is an input you control.

## What the module decides (uniform everywhere, not re-decidable)

| Decision | Standard | Why |
| --- | --- | --- |
| Naming | `<environment>-<name>` (e.g. `prod-orders`) | One convention, no collisions across environments. |
| Networking | Private IP only, in `apps-<environment>`, from the PSA range the network team already provisioned. No public IPv4, ever. | Apps on GKE/Compute Engine reach the DB over the environment VPC. |
| Authentication | IAM database authentication forced on (`cloudsql.iam_authentication = on`, cannot be overridden). No password users. | Every person and workload is a Google identity; the security team audits access by identity. |
| Encryption in transit | `ssl_mode = ENCRYPTED_ONLY` | TLS for every connection. |
| Backups | Automated backups and point-in-time recovery always enabled. | No unprotected databases. |
| Storage growth | `disk_autoresize = true` | Pages at 3 a.m. because a table hit the disk limit are a failure mode, not a feature. |
| Maintenance | A defined weekly window (default Sun 04:00 UTC). | Patching is scheduled, not surprise. |
| Query Insights | Enabled everywhere. | Visibility into every workload with zero extra setup. |
| Labels | `environment` and `managed_by = opentofu` always set. | Auditable, cost-attributable. |
| Deletion | `deletion_protection = true` by default. | Destroying a database is a deliberate two-step act. |

## What you decide (per instance)

`name`, `environment`, `region`, `database_version`, `tier`,
`availability_type` (use `REGIONAL` for anything you care about),
`storage_gb`, `disk_type`, `database_flags`, `databases`, `iam_users`,
`iam_service_accounts`, `labels`, backup retention/window, maintenance
window. All have sane defaults; see `variables.tf` for details.

## Prerequisites

- The environment VPC (`apps-dev` / `apps-staging` / `apps-prod`) exists with
  private services access allocated — owned by the network team, already in
  place. This module consumes it; it never creates networks or PSA ranges.
- Credentials in the environment (`GOOGLE_CREDENTIALS` / ADC). The instance is
  created in `var.project`, or in the credentials' project when unset.

## Usage

Smallest possible instantiation (`minimal.tfvars`):

```hcl
name        = "orders"
environment = "dev"
```

A production database with explicit sizing, HA and identities:

```hcl
name                 = "billing"
environment          = "prod"
project              = "myco-prod"
region               = "europe-west1"
database_version     = "POSTGRES_16"
tier                 = "db-custom-4-16384"
availability_type    = "REGIONAL"
storage_gb           = 100
databases            = ["billing", "billing_audit"]
iam_service_accounts = ["billing-api@myco-prod.iam.gserviceaccount.com"]
iam_users            = ["dba-team@myco.example"]
database_flags = {
  max_connections = "500"
  work_mem        = "32768"  # 32 MiB, set in KiB
}
labels = {
  team    = "dba"
  service = "billing"
}
```

Key outputs: `connection_name` (feed it to `cloud-sql-proxy` or the GKE
sidecar), `private_ip_address`, `instance_name`, `databases`.

## Wiring up access

Creating a database principal (`iam_users` / `iam_service_accounts`) is done
by this module. The companion IAM grants are project-level and stay with the
security team, per our separation of duties:

- `roles/cloudsql.instanceUser` — for the connecting identity, on the project
  (or use a binding scoped to your conventions)
- `roles/cloudsql.client` — for identities connecting via Auth Proxy

## Adopting existing console-created instances

```
tofu import google_sql_database_instance.this projects/PROJECT/instances/INSTANCE-NAME
```

Then write configuration around it. Note that instances whose names don't
match the `<environment>-<name>` convention should be renamed (or recreated
on a maintenance window) before adoption — the module enforces the convention.

## Out of scope (for now)

Read replicas, cross-region replicas, CMEK, PSC connectivity, and
project-level IAM bindings. Ask the platform team if you need one; they're
deliberate additions to this module, not side resources next to it.
