# Private Cloud SQL for PostgreSQL

This root configuration creates one PostgreSQL instance. Use a separate root directory/state and environment-specific tfvars for each instance. Defaults are PostgreSQL 16, regional HA, encrypted private IP only, SSD with automatic storage growth, daily backups and seven days of PITR logs, Query Insights, IAM database authentication, connection/disconnection logging, and deletion protection at both the OpenTofu and Cloud SQL levels. Google-managed encryption at rest is used. These settings incur Cloud SQL, storage, backup and logging charges; choose an appropriate tier and availability type for the workload.

## Prerequisites and deployment

* Enable the Cloud SQL Admin API in the instance project. The execution identity needs permission to manage Cloud SQL instances, databases and users, and to use the specified network (including Shared VPC permissions if applicable). Credentials come from the environment/Application Default Credentials.
* The network team must have established private services access and sufficient allocated IP space on the chosen VPC before apply. This configuration neither creates the VPC nor manages service networking. Use the full network path from the network project, for example `projects/network-host/global/networks/apps-prod`. Select the environment's network explicitly. GKE and VM clients need routes and firewall policies allowing private connectivity.
* Copy `minimal.tfvars` and replace every placeholder with real project, instance, region and network values. It is a syntactically valid example, not a deployable project. Then run `tofu init`, `tofu plan -var-file=your.tfvars`, and `tofu apply -var-file=your.tfvars`. Secure and back up the state using an appropriately access-controlled backend; backend configuration is intentionally left to the operator.

Example additional tfvars:

```hcl
tier              = "db-custom-4-15360"
availability_type = "REGIONAL"
databases         = ["orders"]
iam_users = {
  "dba@example.com"                   = "CLOUD_IAM_USER"
  "orders@my-project.iam"             = "CLOUD_IAM_SERVICE_ACCOUNT"
}
maintenance_window = { day = 7, hour = 4, update_track = "stable" }
labels             = { environment = "prod" }
```

The IAM service account database username is its email **without** `.gserviceaccount.com`; a human username is the full email. For each identity, independently grant Cloud SQL IAM login (`roles/cloudsql.instanceUser`) and, when using a connector, connection access (`roles/cloudsql.client`), at an appropriate scope. GKE workloads should use their workload identity. The module creates database user entries, not IAM role bindings or PostgreSQL database/schema/table privileges; DBAs must grant SQL privileges separately. IAM authentication must use an IAM token, preferably through automatic IAM authentication in the Cloud SQL Auth Proxy or a Cloud SQL connector configured for private IP. Client connections must be encrypted; for direct connections configure TLS and verify the server identity/CA. Merely enforcing encryption does not enforce client certificates or server verification by clients. This module does not create static database passwords. Manage access to the built-in administrative account separately.

## Operations

* The backup window, retention, maintenance window, version, tier, HA mode, initial disk size, optional database names, IAM database users, additional PostgreSQL flags and labels are inputs. `database_flags` cannot override the enforced IAM and connection-logging flags. Cloud Logging retention, log sinks and audit-log policy are managed outside this configuration. Connection logs and Query Insights may contain sensitive operational information; restrict access appropriately.
* PITR requires transaction logs as well as backups; its effective recovery window depends on both. Test restores regularly. Backups and PITR do not replace a separately designed disaster recovery policy. A restore is an operational procedure and is not automated by this root.
* Storage can grow but not shrink. To prevent drift from automatic growth triggering an attempted shrink/replacement, the instance ignores all subsequent changes to `disk_size_gb`. Set the initial value before creation; explicitly expand storage through Cloud SQL when needed and monitor utilization. Automatic growth has no configured size limit and can increase cost.
* Removing an entry from `databases` deletes that database and its data. Removing an IAM user removes the Cloud SQL database user; revoking its IAM grants is separate. Instance deletion is blocked by default. To intentionally destroy an instance, set `deletion_protection = false` and apply first, then run destroy with the same variables. This also disables API-side deletion protection. Review all plans, especially changes to version, network or instance identity, as Cloud SQL may require downtime or replacement.
* Outputs include the private IP and connector connection name; the latter does not imply public connectivity. Cloud SQL and network prerequisites, quotas, available tiers/versions and IAM grants are checked by Google at apply time.
