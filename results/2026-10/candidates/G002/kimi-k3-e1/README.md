# cloudsql-postgres — the DBA team's standard Cloud SQL for PostgreSQL module

One OpenTofu module for every PostgreSQL instance the team runs, replacing
console-provisioned snowflakes with a single, reviewable definition.

## Standardized for every instance (the things you no longer re-decide)

- **Private IP only.** The instance attaches to the environment's VPC
  (`apps-dev` / `apps-staging` / `apps-prod`) over private services access,
  which the network team has already configured. No public IP, no authorized
  networks — the module does not support them on purpose.
- **IAM database authentication, always.** `cloudsql.iam_authentication=on` is
  forced and cannot be overridden by caller-supplied flags. Engineers and
  workloads log in with their Google identity (`CLOUD_IAM_USER` /
  `CLOUD_IAM_SERVICE_ACCOUNT`); the module creates **no password users**.
  Access is therefore attributable to a Google identity, which is what the
  security team audits.
- **TLS in transit.** `ssl_mode = "ENCRYPTED_ONLY"` by default.
- **Backups + point-in-time recovery on**, 7 retained backups, 7 days of
  transaction logs, 02:00 UTC start.
- **Storage autoresize always on** (the configured `disk_size_gb` is a floor),
  with a lifecycle guard so OpenTofu never tries to shrink a grown disk.
- **Query Insights on** (application tags and client addresses recorded).
- **Maintenance window** Sunday 03:00 UTC, `stable` update track.
- **Deletion protection on** by default.

Every one of these is a variable default, so a DBA *can* deviate deliberately
in code review — but never by accident in a console.

## Decisions that stay with the calling DBA

`name`, `project_id`, `region`, `network`, `tier` (required), plus
`database_version`, `edition`, `availability_type` (`REGIONAL` for prod),
`disk_type` / `disk_size_gb`, `database_flags`, the `databases` to create, and
the `iam_users` / `iam_service_accounts` allowed to connect.

## Usage

```hcl
# terraform.tfvars for a production instance
project_id = "payments-prod"
region     = "europe-west1"
network    = "apps-prod"

name              = "pg-orders-prod"
tier              = "db-custom-4-16384"
availability_type = "REGIONAL"
disk_size_gb      = 100

database_flags = {
  max_connections = "500"
}

databases = {
  orders = {}
}

iam_users = [
  "alex.dba@example.com",
]

iam_service_accounts = [
  "orders-api@payments-prod.iam.gserviceaccount.com",
]

labels = {
  environment = "prod"
  team        = "payments"
}
```

`network` accepts a bare name (resolved in `project_id`), a partial path
(`projects/<p>/global/networks/<n>`) or a full self-link, so Shared VPC host
projects work too.

## Operational notes

- Service-account logins must not carry the `.gserviceaccount.com` suffix in
  Cloud SQL; the module strips it for you.
- Besides the database login created here, an IAM principal needs
  `roles/cloudsql.instanceUser` to authenticate. Cloud SQL IAM is granted at
  project level, so that grant is managed by the organization's IAM/security
  tooling (the team that audits access), not by this module.
- Creating an IAM login does not grant it any PostgreSQL privileges. Grant
  roles inside the database after apply, e.g.
  `GRANT app_rw TO "orders-api@payments-prod.iam";`
- Clients authenticate with IAM via the Cloud SQL Auth Proxy / language
  connectors (GKE sidecar, language connectors on Compute Engine), or with
  `psql` using a short-lived OAuth token as the password.
- Read replicas and cross-region DR are deliberately out of scope for now.

## Outputs

`instance_name`, `instance_connection_name`, `instance_self_link`,
`private_ip_address`, `instance_service_account_email`, `database_names`,
`iam_logins`.
