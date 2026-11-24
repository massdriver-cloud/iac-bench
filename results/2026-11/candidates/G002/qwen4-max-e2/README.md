# Standard PostgreSQL on Cloud SQL

Reusable OpenTofu module the DBA team uses to stand up every PostgreSQL
instance. Run directly as a root module; the Google provider is already
configured for the project that holds the apps VPCs.

## What the module standardizes (not configurable)

These are identical on every instance, so nobody re-decides them:

| Standard | Value |
| --- | --- |
| Connectivity | **Private IP only** in `apps-<environment>` (public IPv4 disabled). The network team owns the VPCs and private services access; the module only references the network. |
| Transport security | `ssl_mode = ENCRYPTED_ONLY` — TLS required. |
| Authentication | `cloudsql.iam_authentication = on` — humans and workloads log in as their Google identity (auditable by the security team). No password users. |
| Audit logging | `log_connections` / `log_disconnections` on; Query Insights with application tags and client addresses. |
| Backups | Daily at 02:00 UTC, 14 retained, PITR enabled, 7-day WAL retention. |
| Maintenance | Sunday 03:00 UTC, `stable` update track. |
| Edition / storage | Enterprise edition, disk autoresize enabled, standard `environment` / `engine` / `managed-by` labels. |
| Safety | Deletion protection on (API + OpenTofu) unless explicitly turned off to decommission. |

## What the DBAs own (variables)

Required: `instance_name`, `environment` (`dev` \| `staging` \| `prod`).

Optional with sensible defaults: `region` (`us-central1`), `database_version`
(`POSTGRES_16`), `tier` (`db-custom-2-7680`), `availability_type` (`REGIONAL`
HA), `disk_size_gb` (100), `disk_type` (`PD_SSD`), `disk_autoresize_limit_gb`
(unlimited), `deletion_protection` (`true`), `databases` (extra databases),
`iam_users` (Google identities registered for IAM auth — user emails kept
whole, service accounts trimmed of `.gserviceaccount.com` as Cloud SQL
requires), `user_labels`.

## Usage

```hcl
# tofu plan -var-file=prod.tfvars
instance_name = "pg-orders-prod-01"
environment   = "prod"
tier          = "db-custom-8-30720"
databases     = ["orders"]
iam_users = [
  { email = "orders-api@my-project.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" },
  { email = "dba-oncall@example.com", type = "CLOUD_IAM_USER" },
]
```

`minimal.tfvars` is the smallest valid instantiation (name + environment).

Outputs: instance/connection names, private IP, self link, network, instance
service account, and created databases. IAM roles and in-database `GRANT`s
remain with the DBAs; the module registers identities, it does not decide
authorization.
