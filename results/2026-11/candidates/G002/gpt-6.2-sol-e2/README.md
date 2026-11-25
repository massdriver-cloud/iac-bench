# Cloud SQL for PostgreSQL

This OpenTofu root manages one instance and its optional application databases and IAM logins. Use separate state for each instance. Keep the provider pointed at the project that owns the application's VPC; `environment` selects `apps-dev`, `apps-staging`, or `apps-prod` in that project. Changing the environment of an existing instance is a network migration, not a routine configuration change.

## Plan

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

The Cloud SQL Admin API must be enabled. The selected VPC must already have private services access with sufficient address space. The deployment identity needs permission to read the VPC and manage the declared Cloud SQL resources. If IAM users are configured, it also needs to read and update the project IAM policy. This root does not manage APIs, VPCs, peering, or address ranges. Avoid managing the same conditional IAM bindings with an authoritative IAM policy in another state.

## What stays standard

- Private IP only, with TLS required; no public addresses or authorized networks.
- IAM database authentication and PostgreSQL connection/disconnection logging. The root does not create password users or set a password for the built-in `postgres` account.
- Automated backups (14 retained) and point-in-time recovery (7 days of transaction logs).
- SSD storage with automatic growth, and instance deletion protection in both OpenTofu and Cloud SQL.

DBAs choose the instance name, region, PostgreSQL version, edition, machine tier, initial disk size, and maintenance window. Select a tier that supports `PD_SSD` and your edition, version, and region. Availability defaults to regional HA in `prod` and zonal in `dev` and `staging`; DBAs can override it explicitly. Additional flags are supported, but the IAM and connection logging flags are reserved. An automatically grown disk is accepted as-is on subsequent applies; `initial_disk_size_gb` only sets capacity at creation.

## Connecting and granting access

See `examples/application.tfvars` for a database, a human login, and a workload login. Replace the example identities with existing ones before applying. The root registers each principal with Cloud SQL and adds instance-scoped `roles/cloudsql.instanceUser` and `roles/cloudsql.client` grants. Those grant login and connector access, **not PostgreSQL privileges**. DBAs manage SQL grants and ownership separately, including any restrictions on privileges granted to `PUBLIC`. Bootstrap an authorized DBA through your approved administrative process.

Use the `connection_name` output with the Cloud SQL Auth Proxy or a language connector in private-IP mode with automatic IAM database authentication. GKE workloads should use Workload Identity Federation for GKE to impersonate the registered IAM service account; Compute Engine workloads can use an attached service account with appropriate access scopes. The identity used by the connector for automatic authentication must match the IAM database login. The `iam_database_usernames` output gives the exact PostgreSQL usernames; service account logins omit `.gserviceaccount.com`. A direct connection is also possible over the private IP with a verified TLS connection and an IAM access token.

IAM login provides attributable identities but enabling it does not disable native PostgreSQL password authentication for accounts created or configured outside this root. Keep such accounts under your organization's access policy. PostgreSQL connection logs are not statement-level auditing; Cloud Logging retention, sinks, and Cloud Audit Logs policies remain external.

## Lifecycle

Removing a database from `databases` plans a drop. Review plans and take a verified backup before a destructive change. Reassign any objects owned by an IAM login before removing it. To intentionally decommission an instance, review the dependent resource deletions, protect any data you need to keep, then explicitly change and apply both deletion protections before planning deletion. Do not disable them for normal operation.
