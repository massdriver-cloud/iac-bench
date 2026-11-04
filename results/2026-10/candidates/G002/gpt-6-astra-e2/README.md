# Standard Cloud SQL PostgreSQL root module

One primary instance per root deployment/state. Resources are defined directly; there are no remote modules. Use separate state and variable files for each instance/environment. Provider credentials use Application Default Credentials from the execution environment; no service-account keys or database passwords are inputs or outputs.

## Contract

| Standardized baseline | Rationale |
| --- | --- |
| PostgreSQL, Cloud SQL Enterprise, SSD with automatic disk growth | Predictable operational baseline, not an arbitrary Cloud SQL resource wrapper |
| Private IP only; no public address or authorized networks | Applications connect through their existing environment VPC |
| Existing `apps-dev`, `apps-staging`, or `apps-prod` network | Network team retains ownership of VPCs, address ranges, and private services access |
| IAM database authentication; no password users created | Human and workload access is attributable to existing Google identities |
| TLS required (`ENCRYPTED_ONLY`) | No plaintext database connections; native IAM clients and Cloud SQL connectors both work |
| Daily backups and PITR always on | Recovery is not an opt-in setting |
| Connection/disconnection logging always on | Connection records support identity-based investigation; this is not full SQL statement auditing |
| OpenTofu and Cloud SQL API deletion protection on by default | Teardown needs an explicit reviewed change |

DBAs choose the required PostgreSQL major version, region and machine tier. Optional settings cover HA, capacity/growth ceiling, tuning flags, backup timing/location/retention, maintenance window, databases and IAM identities. Defaults: regional HA, 20 GiB SSD, unlimited disk growth, 14 daily backups, 7 days of PITR logs, daily backup start at 02:00 UTC, and stable-track maintenance on Sunday at 04:00 UTC. Enterprise Plus and replicas are outside this module's scope. Validate version/tier/region compatibility against Cloud SQL before deployment.

The flags `cloudsql.iam_authentication`, `log_connections`, and `log_disconnections` are module-owned. IAM flag overrides are rejected; connection logging flags are always forced on even if included in `database_flags`. Other flags are DBA-managed and may require a restart. Environment and `managed_by` labels always override caller labels.

## Prerequisites and deployment

- An existing Google Cloud project with billing and the Cloud SQL Admin API enabled.
- Existing private services access, with sufficient allocated capacity, on the selected VPC. The module deliberately creates no network, peering, allocated range or API-enablement resources.
- For Shared VPC, set `network_project_id` to the host project. Shared VPC attachment, service-agent permissions and routing are external prerequisites.
- The execution identity needs Cloud SQL resource administration and, when `iam_members` is nonempty, permission to update project IAM policies. No database network connectivity is required just to apply this module.

```sh
tofu init
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` supplies literal values for every required input and creates only the protected primary. Its project/name are illustrative: substitute your real existing project before applying. No application databases or access grants are created unless requested. No actual cloud resources are provisioned by validation or planning.

For a deployment with access and an application database, add these optional settings to your own tfvars:

```hcl
network_project_id = "network-host-dev"
databases = {
  orders = { charset = "UTF8", collation = "en_US.UTF8" }
}
iam_members = {
  "dba@example.com"                         = "USER"
  "orders@dba-platform-dev.iam.gserviceaccount.com" = "SERVICE_ACCOUNT"
  "database-readers@example.com"            = "GROUP"
}
database_flags = {
  log_min_duration_statement = "1000"
}
```

Each identity gets an IAM SQL user plus additive `roles/cloudsql.instanceUser` and `roles/cloudsql.client` grants, conditioned on this instance's resource name and type. Existing project policies are not replaced. Broader grants that already exist elsewhere are not revoked by this module. Service account emails are supplied in full; their SQL usernames automatically omit `.gserviceaccount.com`. Do not simultaneously register an individual identity and its IAM group on an instance if Cloud SQL prohibits the overlap. Group membership and IAM changes can take time to propagate; group members authenticate as themselves.

## Connecting and SQL authorization

Run Cloud SQL Auth Proxy v2 in the selected VPC, using an attached Google identity (GKE Workload Identity Federation mapped to the supplied Google service account, or a Compute Engine service account):

```sh
cloud-sql-proxy --private-ip --auto-iam-authn PROJECT:REGION:INSTANCE
```

Use the `connection_name` output for the last argument. Connect to the proxy's local port 5432 with the IAM SQL username; the proxy supplies and refreshes short-lived credentials. Keep the proxy listener local to the application. Language connectors with private IP and automatic IAM authentication are equivalent. The proxy does not create a network tunnel from outside the VPC: routing to the private endpoint is still required. For direct private-IP connections, use short-lived IAM tokens and properly validated TLS, not a long-lived password; clients own token refresh and server certificate verification.

IAM login rights are **not** PostgreSQL object privileges. DBAs must bootstrap and maintain SQL roles, database/schema/table grants, default privileges, and ownership through a separately authenticated, audited SQL administration workflow. This module does not connect a PostgreSQL provider, grant superuser access, or embed a bootstrap password. Adding a user here alone does not give it application-table access. Handle ownership and grants before removing users; PostgreSQL may refuse to drop roles that still own objects.

## Operations and boundaries

- Tune backup retention and location for recovery/residency requirements; perform restore drills. HA is not backup, and retained daily backups do not extend the configured PITR log horizon.
- Configure capacity alerts, log retention/export, audit-log policy and optional statement auditing in the organization's monitoring/security stack. Connection logging alone is not a complete audit policy. This module does not replace project-wide audit configuration.
- Version changes, tier changes, flags and HA changes can interrupt service. Review plans and Cloud SQL upgrade restrictions. Disks cannot shrink; reconcile configured size/ceiling after automatic growth before capacity changes.
- Instance deletion protection does **not** protect individual databases or users from removal. Changes to database names/encoding/collation and removal of database map entries require particular care.
- For intentional teardown, first set `deletion_protection = false` and apply. Only then destroy, after taking and verifying the required recovery copy. Normal backups/PITR are not a promise of recovery after instance deletion.
- Existing console-managed resources should be imported into the corresponding resource addresses and their plans reviewed before adoption; do not apply this module over an unimported same-name instance.
- Use an organization-managed, access-controlled, encrypted remote state backend with locking for real deployments. Backend location is intentionally not hard-coded in this standalone root.
