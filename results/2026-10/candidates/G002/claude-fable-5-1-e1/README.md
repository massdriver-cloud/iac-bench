# cloudsql-postgres

Standard module for every PostgreSQL instance the DBA team runs on Cloud SQL.

## What is fixed for every instance (not configurable)

| Decision | Setting | Why |
|---|---|---|
| Engine | PostgreSQL only (`POSTGRES_*`) | This is the PostgreSQL module. |
| Network | Private IP only in `apps-<environment>`, no public IPv4 | Workloads live in those VPCs; the network team already peered private services access. |
| Transport | TLS required (`ENCRYPTED_ONLY`, optionally client certs) | No plaintext on the wire. |
| Authentication | `cloudsql.iam_authentication = on`; only IAM users/service accounts are created | Security audits access by Google identity. No shared passwords. |
| Backups | Daily automated backups + point-in-time recovery, always on | Non-negotiable. |
| Logging | `log_connections`, `log_disconnections`, `log_checkpoints`, `log_lock_waits`, `log_temp_files` | Audit and diagnostics baseline. |
| Disk | Auto-resize on; declared size is only the starting point | Never run out of disk. |
| Deletion protection | On by default (API and OpenTofu) | Must be flipped off explicitly to decommission. |
| Labels | `environment`, `managed-by`, `engine` always applied | Inventory. |

## What the DBA decides

Version, edition, tier, HA (`availability_type`, defaults to REGIONAL in prod), disk type/size/ceiling,
PostgreSQL flags, backup window and retention (defaults 30 in prod / 7 elsewhere), WAL retention,
maintenance window and update track, maintenance deny periods, Query Insights, databases to create,
and which Google identities get a login.

## Minimal use

```hcl
project_id  = "my-project"
environment = "dev"
name        = "orders-pg"
```

## Typical use

```hcl
project_id        = "my-project"
environment       = "prod"
name              = "orders-pg"
region            = "europe-west1"
database_version  = "POSTGRES_16"
tier              = "db-custom-4-16384"
database_flags    = { "max_connections" = "400", "work_mem" = "16384" }
databases         = { orders = {}, reporting = { collation = "C" } }
iam_principals = [
  "alice@example.com",
  "orders-api@my-project.iam.gserviceaccount.com",
]
```

Service-account principals get a PostgreSQL role named after the email without the
`.gserviceaccount.com` suffix (Cloud SQL convention); user principals keep their full address.
Grant privileges to those roles inside PostgreSQL as usual. Clients connect over the private IP or
through the Cloud SQL Auth Proxy / language connectors using `connection_name`, with IAM
authentication enabled.

The built-in `postgres` superuser password is not managed here; set it once with
`gcloud sql users set-password postgres --instance=<name> --prompt-for-password` and keep it in the
team secret store.
