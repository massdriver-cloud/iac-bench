# Standard PostgreSQL on Cloud SQL

Root module the DBA team uses to create and manage a Cloud SQL for PostgreSQL
instance (plus optional read replicas, databases and login identities).

```sh
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` is the smallest instantiation; `full.tfvars.example` shows a
production instance with a replica, databases and access.

## The same on every instance (not configurable)

| Area | Standard |
|---|---|
| Network | Private IP only, attached to `apps-<environment>`. No public address. The VPC and its private services access are referenced, never managed here. |
| Transport | TLS required (`ENCRYPTED_ONLY`; may be tightened to require client certificates, never loosened). |
| Authentication | IAM database authentication on. The module creates only IAM users, groups and service accounts; no passwords exist in configuration or state. |
| Audit | `log_connections`, `log_disconnections` and pgAudit are on and cannot be switched off. |
| Recovery | Daily backups and point-in-time recovery on; at least 7 backups kept; backups are retained if the instance is deleted. |
| Safety | Deletion protection in OpenTofu and in the API (default on), storage auto-grow, databases are never dropped by removing them from configuration. |
| Housekeeping | Name `<name>-<environment>`, labels `environment` / `database` / `managed-by`, Query Insights. |

## Decided per instance by the DBAs

Version, edition, machine tier, HA (`availability_type`), initial disk size and
growth ceiling, tuning flags, read replicas, databases (charset/collation),
which identities may log in, backup time/retention/location, maintenance
window, CMEK key, connector enforcement, extra labels.

Environment-dependent defaults, each overridable: prod is `REGIONAL` and on the
`stable` maintenance track; dev and staging are `ZONAL` and on `canary`.

## Access model

`iam_members` takes IAM members (`user:`, `group:`, `serviceAccount:`). For each
one the module creates the matching IAM database user and grants
`roles/cloudsql.client` and `roles/cloudsql.instanceUser` on the project,
conditioned to this instance and its replicas. The `iam_database_users` output
gives the PostgreSQL role name for each member (service accounts drop the
`.gserviceaccount.com` suffix).

New IAM users hold no privileges on database objects. Privileges are granted by
the DBAs in SQL, which requires a `cloudsqlsuperuser`. The built-in `postgres`
user is the only one after creation and has no password, so nobody can log in
as it. To bootstrap grants (typically: make the DBA group a member of
`cloudsqlsuperuser`), a DBA sets a temporary password with
`gcloud sql users set-password postgres --instance=<instance> --prompt-for-password`,
performs the grants, and rotates the password to a discarded random value. That
call is recorded in Cloud Audit Logs; the password policy on the instance
requires 20+ complex characters.

## Prerequisites outside this module

- The Cloud SQL Admin API is enabled in the project.
- `apps-<environment>` exists with private services access (network team). With
  Shared VPC, set `network_project_id` to the host project.
- For pgAudit entries to reach Cloud Logging, Data Access audit logs must be
  enabled for Cloud SQL in the project, and `CREATE EXTENSION pgaudit;` must be
  run once in each database.
- The identity running OpenTofu can administer Cloud SQL and set project IAM
  bindings (only needed when `iam_members` is non-empty).
- With `encryption_key_name`, the Cloud SQL service agent needs
  `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key.

## Decommissioning

Set `deletion_protection = false`, apply, then destroy. Automated backups are
kept after deletion and must be removed separately once no longer needed.
