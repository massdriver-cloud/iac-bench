# Standard Cloud SQL PostgreSQL root module

This root creates one PostgreSQL primary and optionally application databases and IAM database users. It uses native Google resources, not remote modules. Use a separate state and variable file for each instance; never reuse production state for another environment.

## Prerequisites and first plan

- An existing project, billing, and the Cloud SQL Admin API (`sqladmin.googleapis.com`) enabled. APIs and networking are owned outside this module.
- The environment's `apps-dev`, `apps-staging`, or `apps-prod` VPC, with working private services access and sufficient allocated address space. Supply its full path, including the host project for Shared VPC. This module does not create networks, peerings, public IPs, or firewall rules.
- Application and DBA connector hosts must have private routing to that VPC, outbound HTTPS for Google APIs, and TCP 3307 to the private Cloud SQL endpoint. A connector does not create a network tunnel into the VPC. Workloads without public egress need an appropriate Google API access path.
- Application Default Credentials for OpenTofu, with Cloud SQL instance/database/user administration and project IAM policy read/update permissions. Shared VPC provisioning also needs the relevant host-network access. Use your organization's approved deployment identity; never put credentials in tfvars.

`minimal.tfvars` contains literal example project/network identifiers. Substitute existing identifiers before applying in your environment. It intentionally creates no application databases or users; the default `postgres` database remains. It is a valid empty-access baseline, not an application-ready access policy.

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Configure your organization's encrypted, access-controlled remote state backend before real use. None is hardcoded here, so this standalone root can be planned directly.

## Fixed standards and deliberate decisions

| Standard | Reason |
| --- | --- |
| Private IPv4 only, no authorized networks | Applications are already in environment VPCs; the database has no public endpoint. |
| Cloud SQL connectors required; encrypted transport | Clients use the Auth Proxy or a language connector, not unmanaged direct PostgreSQL connections. Connectors perform certificate validation. |
| IAM database authentication always on | Individual Google identities, not module-generated passwords or shared application accounts. |
| Enterprise edition, SSD, automatic unbounded disk growth | Predictable baseline; avoid preventable out-of-space outages. Monitor storage and cost. |
| Daily backups, 14 retained backups, 7 days of PITR logs | Consistent recovery baseline, stored in the instance region. PITR requires an operator-driven restore to a new instance; test restores regularly. These settings are not an RPO/RTO guarantee or cross-region disaster recovery. |
| REGIONAL HA by default | Regional failover baseline; DBAs may deliberately choose ZONAL. HA is not backup or cross-region DR. |
| Both provider and API deletion protection enabled | Protect console/API and OpenTofu deletion. Explicitly disable and apply before intentional destruction. |
| Stable maintenance track | DBA chooses UTC maintenance and backup windows. |

DBAs explicitly select name, project, region, major version, machine tier, and existing network. They also own initial capacity, availability, maintenance timing, PostgreSQL flags (except mandatory IAM authentication), database encoding/collation, and identity membership. The selected tier/version must be supported by Cloud SQL Enterprise in the chosen region. Tuning flags may restart the instance; major upgrades must be tested and are not reversible in place.

The configured disk size is **initial capacity only**: drift is ignored because Cloud SQL cannot shrink a disk after automatic growth. Subsequent manual increases require an explicit operational change outside this setting. Unbounded growth is a conscious availability-over-cost tradeoff.

## Identity-based connections

Example additions to an instance's tfvars:

```hcl
databases = {
  orders = {} # UTF8 / en_US.UTF8; override at creation if needed
}
iam_users = {
  "dba@example.com"                               = "USER"
  "orders@dba-platform-dev.iam.gserviceaccount.com" = "SERVICE_ACCOUNT"
}
database_flags = {
  log_min_duration_statement = "1000"
}
```

Each identity gets a Cloud SQL IAM database user plus additive, instance-conditioned `roles/cloudsql.client` and `roles/cloudsql.instanceUser` project bindings. Existing IAM policies are not authoritatively replaced. Inherited or pre-existing grants can still grant wider access; these bindings cannot restrict those grants. Service-account database usernames omit `.gserviceaccount.com`, as PostgreSQL on Cloud SQL requires. No passwords or service-account keys are generated or held in state. No built-in user/password is provisioned or rotated by this module; out-of-band built-in accounts must be prohibited through organizational policy and audit. Enabling IAM authentication itself does not disable password authentication in the engine.

GKE should use Workload Identity Federation with an appropriately bound Google service account; Compute Engine should use an attached service account with the cloud-platform OAuth scope. Their provisioning is outside this database module. For a DBA with suitable local ADC credentials, for example:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn --address 127.0.0.1 --port 5432 PROJECT:REGION:INSTANCE
psql 'host=127.0.0.1 port=5432 dbname=orders user=dba@example.com sslmode=disable'
```

The local loopback hop is unencrypted in this example; the proxy-to-Cloud-SQL hop is encrypted and verified. Do not expose the proxy listener to untrusted clients. The connector credential identity must match the IAM database username when using automatic IAM authentication. Use automatic IAM in language connectors too, so short-lived tokens refresh without manual password handling.

**Login is not SQL authorization.** DBAs must use an authorized administrative session to grant least-privilege database/schema/table roles and default privileges after provisioning. An IAM user is not made a PostgreSQL administrator by these resources. Plan the initial SQL privilege bootstrap with the existing Cloud SQL administrative process; this root intentionally does not create a shared bootstrap password or run SQL provisioners. Each workload should have its own Google identity. IAM groups and database role/SQL migrations are not managed here. IAM policies provide identity attribution, but SQL statement auditing is separate: configure approved PostgreSQL audit flags/extensions and centrally managed audit-log retention according to security policy; this module does not claim a complete SQL audit trail.

## Removal and recovery

Application databases use `ABANDON`: removing a database from configuration leaves its data in Cloud SQL, and managing it again requires import. **This does not save databases when the entire instance is deleted.** IAM users are deleted normally; transfer ownership and revoke object privileges first if PostgreSQL dependencies prevent removal. Removal also removes only the IAM bindings owned here; check inherited access and terminate existing sessions for urgent revocation.

For intentional destruction: take and verify an independently retained/exported final backup, set `deletion_protection = false`, apply that change, then destroy. Do not assume routine backups survive instance deletion. Name, region, network, and database locale changes may be destructive or rejected; review every plan. No automatic replicas, cross-region recovery, network changes, monitoring alert destinations, project-wide audit configuration, or secrets infrastructure are silently created.
