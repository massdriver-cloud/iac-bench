# Standard Cloud SQL for PostgreSQL

This root module is the DBA team's baseline for Cloud SQL PostgreSQL instances. It deliberately manages the database instance, not the network team's VPC, allocated ranges, or private services access connection.

## Fleet standards

Every instance created by this module has:

- PostgreSQL IAM database authentication enabled (`cloudsql.iam_authentication=on`). The module creates IAM users and IAM service-account users only; it does not create password-based application users.
- A private IP only. Public IP and authorized networks are not exposed as options. The selected network must be `apps-dev`, `apps-staging`, or `apps-prod`, matching the `environment` input.
- TLS required for IP connections (`ssl_mode=ENCRYPTED_ONLY`). Cloud SQL connectors are recommended for GKE and Compute Engine workloads.
- Automated backups, point-in-time recovery, transaction-log retention, and a configurable count-based backup retention policy.
- Query Insights, including client addresses and application tags, plus connection, disconnection, checkpoint, and lock-wait logging.
- Automatic disk growth, a configured maintenance window, standard fleet labels, and API/OpenTofu deletion protection.

Production defaults to `REGIONAL` availability. Development and staging default to `ZONAL`; DBAs can explicitly choose either availability mode.

## DBA-controlled decisions

The inputs expose the PostgreSQL major version, machine tier and edition, availability, initial disk type/size/growth ceiling, databases and collations, IAM principals, additional database flags, backup timing/location/retention, maintenance timing, labels, and deletion protection. IAM authentication, private connectivity, TLS, backups, and PITR are intentionally not optional.

The `database_flags` map can override the module's logging defaults. `cloudsql.iam_authentication` is always merged last as `on`.

## Required prerequisites

1. The Cloud SQL Admin API must be enabled in `project_id`.
2. The caller must have permission to manage Cloud SQL instances, databases, and users.
3. The VPC identified by `network_self_link` must already exist and have private services access configured. A Shared VPC host project may own this network.
4. IAM principals used in `iam_users` must already exist.

This module does not enable APIs or alter VPC peering, so applying it cannot unexpectedly change network-team-owned infrastructure.

## Minimal use

```hcl
# Values in minimal.tfvars
project_id        = "my-database-project"
region            = "us-central1"
instance_name     = "postgres-dev"
environment       = "dev"
network_self_link = "projects/my-database-project/global/networks/apps-dev"
```

```shell
tofu init
tofu plan -var-file=minimal.tfvars
```

A fuller DBA configuration looks like:

```hcl
# Supply with -var-file, or use equivalent module arguments when vendoring this
# directory as a local submodule.
project_id        = "my-database-project"
region            = "us-central1"
instance_name     = "orders-prod"
environment       = "prod"
network_self_link = "projects/my-network-host/global/networks/apps-prod"

database_version = "POSTGRES_16"
tier             = "db-custom-4-16384"
disk_size_gb     = 100

retained_backups = 35
backup_location  = "us"

databases = {
  orders = {
    charset = "UTF8"
  }
}

iam_users = {
  "dba@example.com"                              = "CLOUD_IAM_USER"
  "orders@my-workload-project.iam.gserviceaccount.com" = "CLOUD_IAM_SERVICE_ACCOUNT"
}

database_flags = {
  log_min_duration_statement = "1000"
}
```

## Roles and SQL grants

Cloud SQL creates IAM database principals with the IAM-user role, not with application table privileges or PostgreSQL superuser privileges. Manage `GRANT` statements in the DBA team's reviewed SQL migrations after the instance and schemas exist. This separation keeps identity lifecycle in OpenTofu without requiring this module to hold a privileged database password or connect to a newly created private instance during `tofu apply`.

Workloads authenticate with their existing Google identity through a Cloud SQL connector or Auth Proxy and then log in to PostgreSQL using that identity's email as the database username. For PostgreSQL, service-account usernames use the full service-account email address.

Use `connection_name` and `private_ip_address` to configure connectivity. No database password is generated or exported by this module.
