# PostgreSQL on Cloud SQL

This is a standalone OpenTofu root configuration, one instance per state. Configure a separate backend/state and supply values for each environment; do not reuse one state for dev, staging and production. `minimal.tfvars` is an illustrative plan fixture, not a real project or an instruction to deploy into it.

## Prerequisites

* Enable the Cloud SQL Admin API in the instance project and ensure the deploying identity has the necessary Cloud SQL and network permissions. The network team must have configured private services access (allocated range and service networking connection) on the specified VPC **before** applying. Use the network's host-project path for Shared VPC. This configuration does not create or change the VPC, service networking connection, IAM policies, or API enablement.
* Clients need routing to the private VPC address, appropriate network/firewall rules, and TLS. There is no public IP or authorized public network. SSL mode requires encrypted connections; clients should validate the server certificate or use the Cloud SQL Auth Proxy/connector for authenticated encryption. The connector does not provide network connectivity by itself.
* Grant each login identity `roles/cloudsql.instanceUser` in the instance project (or equivalent permission) outside this configuration. Proxy/connector users also need `roles/cloudsql.client` (or equivalent). Keep those grants scoped according to your IAM policy; this module deliberately does not make project-wide IAM grants. Provision users with `iam_users`, then grant PostgreSQL database/schema/object privileges separately. A Cloud SQL IAM database user alone does not grant access to application data.

## Usage

Copy the fixture and replace all values with real project, region, name, network, and machine tier. Optionally add DBs and identities, for example:

```hcl
databases = ["app"]
iam_users = {
  dba = { email = "dba@example.com", type = "CLOUD_IAM_USER" }
  app = { email = "app@my-project.iam.gserviceaccount.com", type = "CLOUD_IAM_SERVICE_ACCOUNT" }
}
```

The keys are stable OpenTofu identifiers. For PostgreSQL service accounts, the database username is the full email without `.gserviceaccount.com`; the output shows the actual usernames. For GKE, use the workload's Google service account identity; for Compute Engine, use the VM's service account. Configure IAM database authentication in the client (automatic IAM authentication with a compatible Cloud SQL connector is recommended). Token and database privileges are still required. This enables IAM authentication but does not prohibit Cloud SQL's built-in database users or control database-level SQL grants; manage those separately to meet your access policy.

Run `tofu init`, `tofu plan -var-file=your.tfvars`, then review and apply. The credentials are taken from the environment. Use a secure state backend and restrict access to state.

## Standard and operations

Defaults are PostgreSQL 16, regional HA, SSD with automatic growth, encrypted private-only connections, IAM database authentication, daily backups (seven retained) and seven days of transaction logs for point-in-time recovery, stable-channel maintenance and deletion protection. DBAs choose sizing, version, availability, backup window, maintenance window, database names and identities. Retention is not a substitute for testing restores or arranging longer-term/offsite retention if required. HA, backups and storage incur charges; a tier/version/region combination must be supported by Cloud SQL.

`disk_size_gb` sets the initial disk size only. The configuration ignores subsequent disk size changes to avoid fighting automatic growth; to deliberately grow an existing disk, use an operational change outside this configuration. Cloud SQL cannot shrink it in place. Database or user removal from the input deletes the corresponding managed object, subject to Cloud SQL/PostgreSQL restrictions; review plans and migrate data/grants first.

Deletion protection is enabled both in OpenTofu and on the Cloud SQL API. To intentionally delete an instance, set `deletion_protection = false` and apply first, then perform a separate reviewed destroy. Re-enable it if deletion is cancelled. Instance names can remain reserved after deletion; version upgrades or replacement may cause downtime or data loss, so review plans and follow a backup/restore and upgrade procedure.
