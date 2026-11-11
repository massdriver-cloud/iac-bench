# Standard Cloud SQL PostgreSQL

This is a standalone OpenTofu root configuration for one instance. Use separate working directories and state for separate instances/environments; do not share state between them. Supply credentials via the Google provider's environment/Application Default Credentials, and use a secured, access-controlled remote state backend in real deployments. State may contain sensitive metadata. `minimal.tfvars` is a planning example, not a deployable project.

## Prerequisites

* Choose a project, region, unique instance name and a Cloud SQL PostgreSQL-compatible machine tier. Enable the Cloud SQL Admin API in the service project and arrange permissions for the deployer to manage Cloud SQL. The Google provider must be able to access that project.
* The network team must already have configured private services access, including allocated address space and service networking connection, for the chosen VPC. Pass its resource name or self link in `private_network`; for Shared VPC this is the **host** project's network, not necessarily the SQL project. Ensure service networking APIs, cross-project permissions, routes and firewall rules are in place. This configuration does not create or modify network infrastructure. Select the appropriate `apps-dev`, `apps-staging` or `apps-prod` network yourself.
* Client machines/pods need network reachability to the private IP (and appropriate GKE VPC routing). The Cloud SQL Auth Proxy and connectors also need Google API access; they do not create a network path to the private address. For direct connections, configure TLS with server identity verification and trusted Cloud SQL CA certificates. The instance requires encrypted connections but does not itself force clients to verify the server.

Run `tofu init`, edit a copy of `minimal.tfvars` to reference real infrastructure, then `tofu plan -var-file=your.tfvars` and `tofu apply -var-file=your.tfvars`.

## Standard and DBA choices

Each instance has only a private IP, requires encrypted connections, enables IAM database authentication, uses regional HA and SSD with automatic storage increases, retains seven automated backups and seven days of transaction logs for point-in-time recovery, and has a stable maintenance window Sunday at 03:00 UTC. Backups start at 03:00 UTC daily. These settings incur Cloud SQL, backup and storage costs. No cross-region disaster recovery or monitoring/alerting is provisioned. Database flags, version, tier, initial disk size, labels, databases and IAM database users are DBA choices. Verify tier, flags and version compatibility with the chosen region and Cloud SQL before applying; changing flags or version can cause restarts or other disruption. Storage size is an initial size: subsequent automatic growth is ignored by OpenTofu to avoid trying to shrink the disk, so changing `disk_size_gb` later will not resize an existing instance through this configuration.

For example, add the following to your tfvars to create an application database and two IAM database users:

```hcl
databases = ["app"]
iam_users = {
  "alice@example.com"                   = "CLOUD_IAM_USER"
  "worker@example-project.iam"          = "CLOUD_IAM_SERVICE_ACCOUNT"
}
database_flags = { "log_min_duration_statement" = "1000" }
labels = { team = "dba" }
```

The service account's full Google identity in this example is `worker@example-project.iam.gserviceaccount.com`; Cloud SQL PostgreSQL omits the `.gserviceaccount.com` suffix from its database username. IAM database users are distinct from IAM role bindings and PostgreSQL grants. Grant `roles/cloudsql.instanceUser` to identities at an appropriate scope, and, when using the Auth Proxy or a connector, grant `roles/cloudsql.client` as well. Configure PostgreSQL database/schema/table privileges separately. Prefer automatic IAM authentication with a Cloud SQL connector or proxy using the individual user or workload identity; manually supplied IAM tokens are short-lived. The configuration does not grant project-wide IAM roles, manage SQL privileges, disable built-in/password users, or configure database audit logs. Enabling IAM authentication alone does not prevent password-based authentication; audit logging and any policy to restrict other login methods require separate administration.

Both provider-level and Cloud SQL API deletion protection are enabled. To deliberately delete an instance, first review the impact and change both `deletion_protection` and `settings.deletion_protection_enabled` to `false` in the configuration, apply that change, then destroy in a separate operation. Removing an entry from `databases` or `iam_users` deletes that database or user; database deletion can destroy data. Test backup restoration separately.
