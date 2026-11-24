# Private Cloud SQL for PostgreSQL

Use one root deployment and state per instance. Copy `minimal.tfvars`, set a unique instance name, and choose the environment, region, PostgreSQL major version and tier. Run `tofu init`, then `tofu plan -var-file=minimal.tfvars -out=instance.plan`; review before `tofu apply instance.plan`.

The Google provider's project must contain the selected `apps-dev`, `apps-staging` or `apps-prod` VPC with private services access already operational. Compute and Cloud SQL Admin APIs must be enabled. The deployer needs permission to read that network and manage the specified SQL resources. This root does not change network or project IAM policy.

Every instance uses private IP only, encrypted connections, IAM database authentication, auto-growing SSD storage, daily backups (14 retained) and point-in-time recovery (7 days of transaction logs). Initial disk size only applies at creation; later size changes are ignored so an auto-grown disk is never shrunk by a plan. Regional HA and deletion protection are defaults. To retire an instance, first apply `deletion_protection = false`, then review the destroy plan.

## Identity and connectivity

Add human emails to `iam_users` and full workload service account emails to `iam_service_accounts`. These create IAM database logins without storing passwords. The IAM administrator must separately grant `roles/cloudsql.instanceUser` to those identities and `roles/cloudsql.client` when using a connector, scoped to the intended instances. DBAs grant SQL privileges inside each database; a login alone does not grant application data access. Enable Cloud SQL Data Access audit logging for login auditing in the project logging policy.

From a VM or GKE workload with private network reachability and its own Google identity, use the Cloud SQL Auth Proxy v2 with `--private-ip --auto-iam-authn` and the `connection_name` output. Connect through the proxy as the matching IAM database username (for service accounts omit `.gserviceaccount.com`). Use distinct service accounts per workload for attribution. The `private_ip_address` output is available for private TLS clients.

## DBA controls

`variables.tf` defines the interface. Choose compatible Cloud SQL version, edition, region, tier and availability settings. Set `databases` for additional databases, `database_flags` for engine tuning, `backup_start_time` for the UTC backup window and `maintenance_window` for maintenance scheduling. IAM authentication cannot be overridden through the flag map. No local-password users or SQL object grants are provisioned.
