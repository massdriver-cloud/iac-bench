# Standard Cloud SQL PostgreSQL module

The module the DBA team uses to stand up and manage every Cloud SQL
PostgreSQL instance. One instance, its databases, and the Google identities
allowed to log in to it - configured the same way every time.

`minimal.tfvars` is the smallest valid instantiation and plans cleanly.

## Decided once, here - not per instance

| Area | The standard |
|---|---|
| Connectivity | Private IP only, in the `apps-<environment>` VPC (private services access is already configured there by the network team). No public IP and no authorized networks - there is no variable to re-decide this with. |
| Transport | TLS required on every connection, private-IP ones included. |
| Authentication | IAM database authentication only. `cloudsql.iam_authentication=on` is always set and cannot be overridden. No password users, no secrets in state. The built-in `postgres` user is left without a password and therefore cannot be logged into until a DBA deliberately sets one. |
| Authorization to log in | For each registered identity the module creates an IAM database user record on the instance - the per-instance gate: no record, no login - and grants `roles/cloudsql.instanceUser` in the instance's project, the `cloudsql.instances.login` permission IAM logins require. The provider has no per-instance IAM resource for Cloud SQL, which is why that grant is project-scoped; it enables IAM logins and nothing else. The project-level `roles/cloudsql.client` grant that the Cloud SQL connectors need stays with the platform teams that own the workload projects. |
| Backups | Daily automated backups plus point-in-time recovery, always on. |
| Safety | Deletion protection at both the API level and the OpenTofu level; stable maintenance update track. |
| Storage | SSD by default, storage auto-resize on. The autoscaler owns the size after creation; the module ignores drift on `disk_size` because Cloud SQL disks cannot shrink. |
| Observability | Query Insights on, recording client address and application tags. |
| Labels | `environment` and `managed_by=opentofu` are always set and reserved. |

## Environment policy (with per-instance escape hatches)

| | dev | staging | prod |
|---|---|---|---|
| Availability | ZONAL | REGIONAL | REGIONAL |
| Backup retention (days) | 7 | 14 | 30 |
| Transaction log retention for PITR (days) | 1 | 7 | 7 |

Each row has an escape hatch (`availability_type`, `backup_retention_days`,
`transaction_log_retention_days`) for the rare case that genuinely calls for
one; leave them unset to follow policy.

## What the DBA team decides per instance

| Variable | Default | Notes |
|---|---|---|
| `project_id`, `name`, `region`, `environment` | - | Required. |
| `network_project_id` | instance project | Set when the network team keeps the `apps-*` networks in a separate project. |
| `major_version` | `16` | 15, 16 or 17. |
| `tier` | `db-custom-2-7680` | Custom machine types only, so CPU and memory are sized independently. |
| `edition` | `ENTERPRISE` | Opt into `ENTERPRISE_PLUS` per instance. |
| `disk_type` / `disk_size_gb` | `PD_SSD` / `100` | Initial size; the autoscaler grows it afterwards. |
| `preferred_zone` | unset | Zone pinning. |
| `database_flags` | `{}` | Any PostgreSQL flags except the IAM flag. |
| `backup_start_time` | `03:00` | UTC. |
| `pitr_enabled` | `true` | |
| `maintenance_window_day` / `_hour` | Sunday 07:00 UTC | Clear of the backup window. |
| `databases` | `[]` | Databases to create. |
| `iam_users` / `iam_service_accounts` | `[]` / `[]` | Google identities that may log in (people / workloads). |
| `labels` | `{}` | Extra labels, `environment` and `managed_by` reserved. |

## Example

```hcl
# staging.tfvars
name        = "orders-db"
project_id  = "acme-apps-staging"
region      = "europe-west3"
environment = "staging"

major_version = "16"
tier          = "db-custom-4-15360"
edition       = "ENTERPRISE_PLUS"

databases            = ["orders", "orders_reporting"]
iam_service_accounts = ["orders-api@acme-apps-staging.iam.gserviceaccount.com"]
iam_users            = ["jane.doe@acme.com"]

maintenance_window_day  = 7
maintenance_window_hour = 5
backup_start_time       = "02:30"
```

## How workloads connect

- **Cloud SQL connectors** (the usual choice on GKE and Compute Engine): give
  the workload `instance_connection_name` and register its service account in
  `iam_service_accounts`. The connector fetches instance metadata and
  certificates using the workload's own identity.
- **Direct `psql` from inside the VPC**:

  ```
  psql "host=<private_ip_address> port=5432 sslmode=verify-full \
        sslrootcert=<server_ca_certificate> dbname=<db> user=<iam email>"
  ```

  Use an OAuth access token for the identity as the password
  (`gcloud auth print-access-token`).

Roles, `GRANT`s and default privileges are performed by the DBAs with psql or
the team's migration tooling; Cloud SQL has no API for them, so they are
deliberately outside this module.

## Non-goals (deliberate)

- **Read replicas** - a separate concern; they change how users and databases
  must be created and are not part of "an instance".
- **CMEK** - add `encryption_config` when the security team mandates a key.
- **Password users and Google Groups** - access must stay attributable to a
  Google identity for the security team's audits (and Cloud SQL IAM database
  authentication does not support groups anyway).
- **Private services access** - owned and operated by the network team.

## Deleting an instance

Deliberately a two-step, reviewed act: flip `deletion_protection` and
`settings.deletion_protection_enabled` to `false` in a reviewed change, apply,
then destroy.
