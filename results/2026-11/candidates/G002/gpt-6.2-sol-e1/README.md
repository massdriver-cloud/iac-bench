# Cloud SQL for PostgreSQL

This OpenTofu root module manages one primary instance. Give each instance its own state and keep its `.tfvars` under review so the configuration, rather than the console, records DBA decisions.

## Prerequisites and use

Use the Google provider's project configuration and environment credentials. The project must have the Compute Engine and Cloud SQL Admin APIs enabled. The network team must already have configured private services access on the selected `apps-dev`, `apps-staging`, or `apps-prod` VPC. This module reads that VPC; it does not manage the network, allocated ranges, or the service networking connection. The OpenTofu runner needs permission to read the VPC and manage Cloud SQL. If you configure IAM logins, it also needs permission to read and update the project IAM policy.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

`minimal.tfvars` creates an instance with no custom databases or IAM logins. Copy it for a deployment or start from `example.tfvars` for an example with a database and IAM logins. Replace the example IDs, sizing, and identity emails as appropriate. Review the plan before applying. See `variables.tf` for the full list of settings and defaults.

## What is standard, and what DBAs choose

- **Networking and access:** private IP on the environment VPC, no public IP, encrypted transport, Cloud SQL connector required, IAM database authentication enabled, and PostgreSQL connection and disconnection logging enabled. These are not per-instance toggles. The module doesn't change audit-log routing, retention, or project-wide audit settings.
- **Recovery and storage:** daily backups and point-in-time recovery are always on. Defaults are a 03:00 UTC backup window start, 14 backups, and seven days of PITR logs. DBAs can set the schedule and retention. The SSD autogrows; the initial disk-size input is create-time only so growth will not cause a shrink or replacement plan. For a planned capacity increase on an existing instance, increase the disk using Cloud SQL and keep the configured initial size appropriate for future instances.
- **Sizing and operations:** DBAs choose the version, region, and tier. Edition defaults to Enterprise; choose a tier supported by the edition and region. Production defaults to regional HA; dev and staging default to zonal, with an explicit override available. DBAs may set a maintenance window, additional PostgreSQL flags, labels, databases, and IAM logins. Review flags for version compatibility and restart requirements.
- **Deletion:** both OpenTofu and Cloud SQL instance deletion protection are enabled. Managed databases also have an OpenTofu lifecycle guard. Planned decommissioning requires reviewed changes to the protection settings and an apply to clear Cloud SQL's API-level instance protection before deletion. Keep the resource definitions in place until protections can be removed deliberately; removing a database resource block also removes its lifecycle guard.

## Database access

The module registers existing IAM identities as database users and adds `roles/cloudsql.client` and `roles/cloudsql.instanceUser` grants restricted by IAM conditions to this instance. It does not grant PostgreSQL object privileges: DBAs must grant database, schema, and object privileges separately using SQL. Don't manage these grants alongside authoritative project IAM bindings that would overwrite them. For `CLOUD_IAM_GROUP`, register the group email and use members' individual identities to connect. Don't register a group member individually on the same instance if they should use group authentication. Removing an IAM login may require first transferring object ownership or cleaning up dependencies in PostgreSQL.

Run a Cloud SQL language connector or the Cloud SQL Auth Proxy from your VPC-connected workload with automatic IAM database authentication and private IP selected, using the `connection_name` output. For example, with Auth Proxy v2:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn "$(tofu output -raw connection_name)"
```

The connector must run as the Google identity logging in to the database; use Workload Identity Federation for GKE or the appropriate attached service account on Compute Engine. Use the username from `iam_login_names` for individually registered identities. For service accounts it omits `.gserviceaccount.com`, as PostgreSQL on Cloud SQL requires. Human access also requires a network path to the private IP.

No password-based users or passwords are provisioned by this module. For first-time SQL privilege setup, use your security team's controlled bootstrap procedure. If it uses Cloud SQL's built-in `postgres` account, set a temporary password through the Cloud SQL control plane (not in OpenTofu), connect over the private proxy without `--auto-iam-authn`, and grant the designated IAM DBA the required SQL privileges. Verify the IAM login and remove the temporary password before handing over the instance. Cloud SQL retains its built-in accounts; enabling IAM authentication does not prohibit passwords set outside OpenTofu.
