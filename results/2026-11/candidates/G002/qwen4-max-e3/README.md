# Standard PostgreSQL (Cloud SQL) module

The DBA team's single way to stand up PostgreSQL on Cloud SQL. Every instance
built with this module is configured identically where it should be, and
exposes only the decisions that genuinely belong to the DBAs.

## What is standardized (not configurable per instance)

| Area | Standard |
|---|---|
| Network | Private IP **only** on the environment's `apps-<env>` VPC (`apps-dev`, `apps-staging`, `apps-prod`). The network team owns these networks and has already configured private services access; this module only attaches. No public IPv4, no authorized-networks allowlists. |
| Transport security | `ssl_mode = ENCRYPTED_ONLY` — TLS required even inside the VPC. |
| Authentication | `cloudsql.iam_authentication = on`. Database logins are Google identities (users and service accounts), which is what the security team audits. No password users, no root password. |
| Backups | Always enabled, PITR always on, 02:00 UTC start, 7 days of WAL retention; retained backups: dev 7 / staging 14 / prod 30. |
| Availability | dev `ZONAL`, staging & prod `REGIONAL` (HA). |
| Maintenance | Sunday 03:00 UTC; dev on the `canary` update track, staging/prod on `stable`. |
| Storage | PD-SSD with autoresize. |
| Edition | ENTERPRISE. |
| Logging | Mandatory flags: connections, disconnections, checkpoints, lock waits, temp files, statements > 1s; Query Insights on. |
| Encoding | Application database created as UTF8 / `en_US.UTF8`. |
| Safety | Deletion protection on by default (OpenTofu + API level). |
| Labels | `managed-by=opentofu`, `environment=<env>`, `component=postgresql` (+ your labels). |

## What the DBAs decide

Required: `instance_name`, `environment`, `region`, `tier`, `database_name`.

Optional (standard defaults): `database_version` (POSTGRES_16),
`iam_database_users` (Google identities granted DB login),
`database_flags` (extra tuning; mandatory flags cannot be overridden),
`labels`, `deletion_protection` (true).

## Usage

The Google provider must be configured for the project that owns the
`apps-*` networks (instances are created in that same project).

```hcl
module "orders_db" {
  source = "./" # or the published location of this module

  instance_name = "orders-prod"
  environment   = "prod"
  region        = "us-central1"
  tier          = "db-custom-8-30720"
  database_name = "orders"

  iam_database_users = [
    { email = "orders-svc@my-project.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
    { email = "dba-oncall@example.com",                        type = "CLOUD_IAM_USER" },
  ]
}
```

Grant the IAM principals the `roles/cloudsql.instanceUser` role (and
`roles/cloudsql.client` if they use connectors) separately; database-level
privileges are then granted in PostgreSQL to the IAM identity, e.g.
`GRANT ... TO "orders-svc@my-project.iam"`.

`minimal.tfvars` is the smallest valid instantiation (a disposable dev
instance) and plans cleanly:

```
tofu plan -var-file=minimal.tfvars
```
