# Cloud SQL PostgreSQL — standard instance module

This root module is how the DBA team provisions PostgreSQL on Cloud SQL. It
encodes every decision that should be identical across all instances and
exposes only the knobs that are genuinely per-instance. Instances created
with it are private, identity-authenticated, backed up and auditable by
default — there is no configuration in which they are not.

## Quick start

```
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` shows the smallest valid instantiation:

```hcl
project     = "acme-dba-postgres-dev"
name        = "orders"
environment = "dev"
region      = "us-central1"
```

`environment` picks the network — `apps-dev`, `apps-staging` or `apps-prod`,
owned by the network team with Private Service Access already allocated on
each. That is the only networking decision a DBA ever makes.

## What the module decides (same on every instance)

| Area | Rule |
|---|---|
| Networking | Private IP only. No public IPv4, no authorized networks to manage. The instance attaches to `apps-<environment>` through PSA. |
| Authentication | IAM database authentication locked on (`cloudsql.iam_authentication=on`). The module has no concept of database passwords and never creates password users. |
| Auditing | `log_connections` / `log_disconnections` locked on; Query Insights enabled. |
| Encryption in transit | `ssl_mode = ENCRYPTED_ONLY`, even on the private network. |
| Encryption at rest | Google-managed by default; optional CMEK via `encryption_key_name`. |
| Backups | Always on, with point-in-time recovery and the full 7-day transaction-log window. Window 02:00 UTC; retention 1–35 daily backups (`backup_retention_days`, default 14). |
| Disk | `PD_SSD` only, with storage auto-resize so a full disk never takes a database down. |
| Maintenance | Sundays 04:00 UTC, `stable` update track. |
| Labels | `env = <environment>` and `managed-by = opentofu` applied automatically. |
| Protection | `deletion_protection` defaults to `true` and can never be disabled in prod. |

## What the DBAs decide (per instance)

Required: `project`, `name`, `environment`, `region`.

Optional, with deliberate defaults: `database_version`, `tier`,
`availability_type`, `disk_size_gb`, `backup_retention_days`,
`database_flags`, `iam_database_users`, `labels`, `deletion_protection`,
`encryption_key_name`, `allocated_ip_range`, `network_project`.

Guardrails enforced by variable validation:

- `environment` must be `dev`, `staging` or `prod`.
- prod instances must be `REGIONAL` (highly available) and
  deletion-protected; `ZONAL` is a cost trade-off allowed only below prod.
- `database_version` is allowlisted (`POSTGRES_13`–`POSTGRES_17`).
- Locked database flags (`cloudsql.iam_authentication`, `log_connections`,
  `log_disconnections`) and baseline labels cannot be overridden.

See `variables.tf` for full descriptions.

## Granting access

Every engineer and workload already has a Google identity; access is granted
to those identities and audited as such:

1. Give the principal the Cloud SQL IAM roles it needs (e.g.
   `roles/cloudsql.client`).
2. Add its email to `iam_database_users` so the module creates the matching
   database role (IAM users and service accounts only).
3. Connect from `apps-<environment>` (GKE or Compute Engine) via the Cloud
   SQL Auth Proxy or any TLS-capable client, using the `private_ip_address`
   or `connection_name` outputs.

The instance's own service account is exposed as
`instance_service_account` for any grants it needs (for example on a CMEK
key).
