# Cloud SQL for PostgreSQL

Use one root state per instance. Copy `minimal.tfvars` for a new instance, select its environment, name, region, PostgreSQL version and compatible machine tier, then run `tofu init` and `tofu plan -var-file=minimal.tfvars`. Review the plan before applying it. The Google provider's project must contain the selected `apps-dev`, `apps-staging` or `apps-prod` VPC with working private services access. Enable the Compute Engine and Cloud SQL Admin APIs beforehand. The module reads the VPC; it does not create or change networking or enable project services.

## Connection and access

There is no public IP. Run clients on a network with a route to the private endpoint. For example, on GKE or Compute Engine, run the Cloud SQL Auth Proxy v2 as the workload's Google identity using `cloud-sql-proxy --private-ip --auto-iam-authn INSTANCE_CONNECTION_NAME`, substituting the `connection_name` output. Connect to its local listener as that IAM database user. For direct connections configure certificate verification on the client; the server requires TLS.

`iam_users` registers the supplied identities on the instance, without passwords. Use full emails as keys, with values `CLOUD_IAM_USER` or `CLOUD_IAM_SERVICE_ACCOUNT`. For service accounts the PostgreSQL login name omits the `.gserviceaccount.com` suffix. Registration does not grant project IAM roles or SQL object privileges. Grant authorized identities `roles/cloudsql.instanceUser` (and `roles/cloudsql.client` for the proxy/connector) with appropriate IAM scope outside this root. Grant application-specific PostgreSQL privileges separately. Use distinct identities rather than shared logins so database users can be traced to people or workloads. Enabling IAM authentication does not disable Cloud SQL's built-in roles; this module does not provision password logins.

## Operations

Regional HA and deletion protection are on by default. Backups run daily with seven retained backups and seven days of transaction logs for point-in-time recovery. Set the backup start time and maintenance window in UTC. SSDs grow automatically; `disk_size_gb` only controls initial allocation. Choose edition, tier and HA together according to Cloud SQL's regional capabilities. Additional PostgreSQL flags can be supplied in `database_flags`; IAM authentication is not overridable. For session audit logging, set `log_connections` and `log_disconnections` as supported by your PostgreSQL version, and manage log access, retention and export in your logging project.

Removing an entry from `databases` plans deletion of that database; instance deletion protection is not a backup or a guard against individual database drops. To retire the whole instance, verify recovery requirements, apply `deletion_protection = false` first, then plan destruction.
