# Cloud SQL PostgreSQL — the DBA team's standard module

One instantiation of this module is one PostgreSQL deployment on Cloud SQL: a
primary instance, its databases, its logins, and any read replicas, attached
to a team VPC over private services access. Applications run on GKE and
Compute Engine in the per-environment networks (`apps-dev`, `apps-staging`,
`apps-prod`); the network team owns those networks and has already configured
private services access on each.

The module exists so that every instance is configured the same way where
that is a matter of policy, while the decisions that genuinely belong to the
DBA team stay in their hands, per instance.

## What this module standardizes (the same everywhere)

These are deliberate module-level decisions. Where they are not variables at
all, the module cannot be talked out of them:

- **Private IP only.** Instances get an address in the team's VPC through
  private services access. No public IP, no authorized networks, no way to
  enable them from this module.
- **TLS is required.** `ssl_mode = ENCRYPTED_ONLY`: every connection from
  GKE, Compute Engine or a DBA's workstation must be encrypted.
- **IAM database authentication is the access model.** Logins are Google
  identities — engineers as their user email, workloads as their service
  account — so database access maps to the identities the security team
  audits. No passwords are managed for IAM logins. Password logins exist only
  as an explicit, empty-by-default `builtin_users` escape hatch for
  migration tooling and vendor support.
- **Backups are always on**: daily, starting 03:00 UTC, 7 days retained,
  point-in-time recovery enabled with 7 days of write-ahead logs by default.
  A database without backups is a misconfiguration, not a choice.
- **Deletion protection is on by default**, at both the Terraform level
  (destroy is refused) and the Cloud SQL API level (the console refuses too).
- **Query Insights is on**, recording client addresses and application tags,
  with the standard 1024-character query string length.
- **A standard maintenance window** (Sunday 05:00 UTC).
- Every instance carries a `managed-by = opentofu` label.
- Data at rest is encrypted with Google-managed keys (the Cloud SQL default).

## The decisions that stay with the DBA team

Per instance, via variables:

- engine version (`database_version`), `edition`, `tier`, `disk_size`,
  `disk_type`, `disk_autoresize[_limit]`
- `availability_type` (ZONAL vs REGIONAL HA), `zone` pinning, and read
  `replicas` — same-region or cross-region, each with its own tier, disk and
  availability type
- PostgreSQL `database_flags` (e.g. pgaudit for statement-level audit
  logging, connection limits, logging verbosity)
- which `databases` exist, with optional charset and collation
- who can log in (`iam_users`), and which principals also need
  `roles/cloudsql.client` for the Cloud SQL Auth Proxy and language
  connectors
- `user_labels`, `network_project_id` / `allocated_ip_range` for Shared VPC
  setups, and the tunable standards: backup window, retention, PITR,
  maintenance window, Query Insights

## Prerequisites

- Private services access is configured on the target network by the network
  team — including every region that a cross-region replica will run in.
- Principals listed in `iam_users` already exist as Google identities.
- The module grants `roles/cloudsql.instanceUser` (and, where requested,
  `roles/cloudsql.client`) on `project_id` — those are additive grants, so
  the security team keeps ownership of the rest of the project's IAM.

## Usage

The module is applied directly as a root module. The smallest valid
instantiation is in `minimal.tfvars`. A fuller one:

```hcl
project_id        = "apps-prod-9c2f"
region            = "europe-west4"
name              = "orders-prod"
network           = "apps-prod"
tier              = "db-custom-8-30720"

availability_type = "REGIONAL"
disk_size         = 200

database_flags = {
  "log_min_duration_statement" = "1000"
  "shared_preload_libraries"   = "pgaudit"
}

databases = {
  orders    = {}
  reporting = { collation = "en_US.UTF8" }
}

iam_users = {
  "dba@example.com"                                   = {}
  "orders-api@apps-prod-9c2f.iam.gserviceaccount.com" = {
    grant_cloudsql_client = true
  }
}

replicas = {
  "read-1"  = {}
  "read-dr" = { region = "europe-west8", tier = "db-custom-4-15360" }
}
```

## Connecting

- Directly from the network, with TLS and an IAM token:

  ```
  psql "host=<private_ip_address> sslmode=require dbname=orders user=<login_name>"
  ```

  The `iam_login_names` output gives each principal's exact login name:
  service accounts log in as their email without the `.gserviceaccount.com`
  suffix (e.g. `orders-api@apps-prod-9c2f.iam`).
- Via the Cloud SQL Auth Proxy or a Cloud SQL language connector: use the
  `connection_name` output, and give the connecting principal
  `grant_cloudsql_client = true`.

## Notes

- Cloud SQL IAM database authentication supports users and service
  accounts; Google Groups are not supported as database logins.
- Flags that require a restart will restart the instance when applied.
- To destroy a protected instance, first set `deletion_protection = false`
  and apply, then destroy. This friction is intentional.
