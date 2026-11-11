# PostgreSQL on Cloud SQL — standard instance module

The DBA team's single way to stand up a PostgreSQL instance on Cloud SQL.
Every design decision below is made once, here, instead of once per instance
in the console; everything that genuinely varies between databases stays an
input.

## What the module standardizes (fixed for every instance)

| Decision | Standard | Why |
|---|---|---|
| Connectivity | Private IP only (`ipv4_enabled = false`), attached to the environment's VPC network — `apps-dev`, `apps-staging` or `apps-prod`, chosen from `environment` | Workloads live in those networks; private services access on each is already provisioned by the network team (the module consumes it and never touches networks or PSA ranges). |
| TLS | `ssl_mode = "ENCRYPTED_ONLY"` | All connections encrypted in transit. |
| Authentication | IAM database authentication only — `cloudsql.iam_authentication = on` is always merged into the database flags (and wins any conflict) | No password users are ever created. The security team audits database access by Google identity; engineers and GKE/Compute Engine workloads already have Google identities. |
| Backups | Automated daily backups and point-in-time recovery always enabled | PITR is not optional anywhere. |
| Destruction safety | `deletion_protection` defaults to `true` (both OpenTofu-level and API-level) | Production databases don't get destroyed by accident; it must be explicitly relaxed. |
| Labels | `environment` and `managed-by = opentofu` on every instance | Consistent fleet inventory. |

## What DBAs decide per instance (inputs, with defaults)

- `name`, `environment` (required) — instance identity and target environment/network.
- `postgresql_version`, `tier`, `edition`, `availability_type` — engine and shape (use `REGIONAL` HA for production).
- `disk_type`, `disk_size_gb`, `disk_autoresize`, `disk_autoresize_limit_gb` — storage.
- `iam_users` — Google identities (user or service-account emails). Each gets a Cloud SQL IAM database user **and** is granted `roles/cloudsql.instanceUser`, which is what lets it actually connect via IAM authentication (Cloud SQL Auth Proxy, GKE, Compute Engine). The provider has no instance-scoped Cloud SQL IAM resource, so the grant is made at project scope; set `grant_instance_user_role = false` if the security team manages those grants out of band.
- `databases` — databases created at provision time.
- `database_flags` — PostgreSQL tuning flags (layered under the module's required flags).
- `maintenance_window`, `backup_start_time`, `backup_retention_days`, `transaction_log_retention_days` — operational scheduling.
- `region`, `zone`, `project_id`, `network_project_id`, `allocated_ip_range`, `user_labels`, `deletion_protection` — placement and lifecycle overrides.

## Usage

```hcl
module "orders_prod" {
  source = "./"   # this module, instantiated per database

  name        = "orders-prod"
  environment = "prod"

  region             = "europe-west1"
  postgresql_version = "16"
  tier               = "db-custom-4-15360"
  availability_type  = "REGIONAL"

  iam_users = [
    "alice@example.com",
    "orders-api@my-project.iam.gserviceaccount.com",
  ]
  databases = ["orders"]
}
```

The smallest valid instantiation is `minimal.tfvars` (just `name` and
`environment`).

## Prerequisites

- The environment VPC networks (`apps-dev`, `apps-staging`, `apps-prod`) with
  private services access already configured — owned by the network team.
- Credentials from the environment; the principal needs Cloud SQL admin
  rights in the target project, `roles/compute.networkUser` if the network
  lives in a Shared VPC host project (`network_project_id`), and project IAM
  write access if `grant_instance_user_role` is on.

## Outputs

`connection_name`, `private_ip_address`, `self_link`, `network`, the
instance's service account email, and the provisioned IAM users/databases.
