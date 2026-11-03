# cloudsql-postgres

Standard Cloud SQL for PostgreSQL module for the DBA team. One instance per
module call; plan and apply it as a root module.

## What is the same on every instance (not configurable)

| Concern | Decision |
|---|---|
| Network | Private IP only on `apps-<environment>` via the existing private services access peering. No public IP, no authorized networks. Private path for Google services enabled. |
| Transport | TLS required (`ENCRYPTED_ONLY` by default; client certs can be demanded on top). |
| Authentication | `cloudsql.iam_authentication = on`. Principals are Google identities (users, groups, service accounts) so the security team can audit access by identity. No password users unless `break_glass_admin` is explicitly set. |
| Auditability | `log_connections` / `log_disconnections` on; Query Insights on with client address and application tags. |
| Durability | Daily automated backups with point-in-time recovery; `deletion_protection` on by default and cannot be turned off in prod. |
| Maintenance | `stable` update track with a fixed weekly window (day/hour configurable). |
| Disk | Auto-resize on; the module never shrinks or fights the current size. |

## Environment-aware defaults (overridable)

| Setting | prod | dev / staging |
|---|---|---|
| `availability_type` | `REGIONAL` | `ZONAL` |
| `retained_backups` | 30 | 7 |

## What the DBA decides

Engine version, edition and tier, disk size/type/limit, zone preferences,
extra `database_flags`, backup window/location/WAL retention, maintenance
window and deny periods, CMEK key, databases, IAM principals, labels.

## Minimal use

```hcl
project_id  = "my-project"
name        = "orders"
environment = "dev"
region      = "europe-west1"
```

See `example-prod.tfvars` for a fuller instance.

## Access

* `iam_users` – user or service-account emails. Each becomes a Cloud IAM
  database user; service accounts log in as `<name>@<project>.iam`
  (the `.gserviceaccount.com` suffix is dropped by Cloud SQL).
* `iam_groups` – Google Groups; members log in as themselves.
* `grant_iam_login_roles` (default `true`) grants `roles/cloudsql.instanceUser`
  and `roles/cloudsql.client` on the project to each principal. If the same
  principal is listed on several instances in one project, set this to `false`
  on all but one (or manage those roles centrally) to avoid two module
  instances owning the same binding.
* Database-level privileges (`GRANT ...`) remain a DBA task inside PostgreSQL;
  the module stops at authentication.
* `break_glass_admin` – optional built-in (password) admin for emergencies.
  The password is generated and stored in Secret Manager as
  `<instance>-<user>-password`; it never appears in outputs.

## Notes

* Instance names get a 4-character random suffix by default because Cloud SQL
  reserves a deleted instance's name for about a week. Set
  `use_random_suffix = false` for a fixed name.
* The VPC is referenced by path, not looked up, so the module does not need
  read access to the network host project at plan time. Use
  `network_project_id` for a shared VPC host, or `network_self_link` to point
  at a non-standard network.
