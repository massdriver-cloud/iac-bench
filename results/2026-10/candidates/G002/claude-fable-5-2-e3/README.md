# Cloud SQL for PostgreSQL: standard instance

Root module for one PostgreSQL instance (plus optional read replicas,
databases and access grants), configured the same way every time.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

`minimal.tfvars` is the smallest valid instance. `full.tfvars` sets every
optional input and is only there as a worked example.

## What you decide per instance

| Input | Notes |
|---|---|
| `project_id`, `name`, `region` | The name is used as-is. |
| `environment` | `dev`, `staging` or `prod`. Selects the `apps-<environment>` network and the defaults below. |
| `database_version` | `POSTGRES_14` to `POSTGRES_17`. No default, so a module update can never upgrade an instance. |
| `tier`, `edition`, `disk_size_gb`, `disk_autoresize_limit_gb` | Sizing. `edition` defaults to `ENTERPRISE`. |
| `high_availability` | Default: regional in prod, zonal elsewhere. |
| `backup_*`, `transaction_log_retention_days` | Schedule and retention. Default retention: 30 backups in prod, 7 elsewhere; 7 days of WAL. |
| `maintenance_window`, `deny_maintenance_period` | Default window: Sunday 06:00 UTC. |
| `database_flags`, `pgaudit_extra_classes` | PostgreSQL tuning and extra audit classes. |
| `databases`, `iam_members`, `read_replicas` | What lives on the instance and who may log in. |
| `kms_key_name`, `allocated_ip_range`, `network_project_id`, `zone`, `labels` | Optional placement, encryption and labelling. |
| `deletion_protection` | Default `true`. |

## What is the same everywhere (not configurable)

- **Network:** private IP only, on `apps-<environment>`. No public address and
  no authorized networks. TLS is required on every connection.
- **Access:** IAM database authentication is on. The module creates no
  password users and stores no credentials in state. Each `iam_members` entry
  gets a PostgreSQL role and Cloud SQL Client / Instance User grants that are
  conditioned on this instance and its replicas.
- **Audit:** connections and disconnections are logged, and pgAudit logs all
  DDL and role/privilege changes. These flags cannot be overridden.
- **Recovery:** daily backups and point-in-time recovery are always on.
  Backups are kept, and a final backup is taken, if the instance is deleted.
- **Storage:** SSD with auto-grow.
- **Observability:** Query Insights with client address and application tags.
- **Maintenance:** dev and staging are on the `canary` track, prod on
  `stable`, so prod gets Cloud SQL releases after the other environments.
- **Labels:** `environment` and `managed-by` on every instance.

## Things to do outside the module

- **Privileges inside PostgreSQL.** The module creates the roles for the
  Google identities; what they may do is granted in SQL. The first grants
  need the built-in `postgres` user, which has no password until an admin
  sets one (`gcloud sql users set-password postgres ...`). Treat that as the
  break-glass path; setting it is recorded in the project's admin activity
  log.
- **pgAudit extension.** The flags are set, but `CREATE EXTENSION pgaudit;`
  must be run once in each database for statements to be logged.
- **Data Access audit logs.** pgAudit entries are delivered to Cloud Audit
  Logs only if Data Access logging is enabled for the Cloud SQL API in the
  project. That is a project-wide setting and is not managed here.
- **Customer-managed keys.** If `kms_key_name` is set, the Cloud SQL service
  agent must already hold `roles/cloudkms.cryptoKeyEncrypterDecrypter` on it.

## Prerequisites

- The Cloud SQL Admin API is enabled in the project.
- Private services access exists on `apps-<environment>` (owned by the
  network team). If that network is in a Shared VPC host project, set
  `network_project_id`.
- The identity running OpenTofu can administer Cloud SQL and, if
  `iam_members` is used, can change the project's IAM policy.

## Behaviour worth knowing

- Removing an entry from `databases` stops managing the database but does not
  drop it.
- Removing an entry from `iam_members` removes the IAM grants and drops the
  PostgreSQL role. PostgreSQL refuses to drop a role that still owns objects;
  reassign them first.
- `disk_size_gb` is the initial size. Later changes to it are ignored, because
  auto-grow would otherwise be reverted.
- To decommission: apply with `deletion_protection = false`, then destroy.
  Cloud SQL does not allow the instance name to be reused for about a week.
