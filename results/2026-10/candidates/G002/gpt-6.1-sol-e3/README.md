# Standard Cloud SQL PostgreSQL root

A standalone OpenTofu root creating one PostgreSQL primary, optional application databases, and optional IAM database identities. No remote modules, VPC creation, peering, PSA ranges, passwords, or service-account keys. Use a separate state and configuration per instance/environment. Remote state storage, locking and access controls are deployment concerns; configure a protected backend before production use.

## Contract and design

| Standard | Implementation |
| --- | --- |
| Private connectivity | Existing `apps-dev`, `apps-staging` or `apps-prod` VPC with PSA; public IPv4 off, no authorized networks. Supports a Shared VPC host-project self-link. |
| Encrypted, identity-based connections | Cloud SQL connector enforcement, encrypted-only TLS, IAM database authentication always on. Clients must use a Cloud SQL Auth Proxy or language connector, with private IP and automatic IAM authentication. |
| No module-managed database credentials | Only IAM users, service accounts and groups are provisioned. No password inputs, generated passwords, keys or password outputs. Enabling IAM does not disable every possible native PostgreSQL login: do not create application password users out of band. Any break-glass administrator must be separately controlled and audited. |
| Access by named identity | Additive, non-authoritative `roles/cloudsql.client` and `roles/cloudsql.instanceUser` grants, conditioned on this instance's resource name and type. Other instances' bindings are not replaced. Existing broader IAM grants remain effective; this module cannot narrow them. |
| Audit baseline | Mandatory connection/disconnection logs, `cloudsql.enable_pgaudit=on`, and `pgaudit.log=all`. DBAs must install `CREATE EXTENSION IF NOT EXISTS pgaudit;` in application databases using their privileged migration process. Review audit completeness after deployment. Logs use Cloud Logging; central log routing, restricted access and retention are owned by security, not created here. SQL audit logs can contain sensitive statements and generate significant volume. |
| Recovery | Daily automated backups, 14 retained by default, and PITR with seven days of transaction logs. Backups cannot be disabled. |
| Availability/storage | Enterprise edition, regional HA by default, SSD with unrestricted automatic growth. Explicit ZONAL is available for lower-cost nonproduction deployments. Monitor capacity and costs. |
| Lifecycle | Both provider-side and API deletion protection enabled by default; a declared weekly UTC maintenance window. The SQL Admin API is enabled and left enabled on teardown. |

DBAs choose project, region, instance name, PostgreSQL major version and machine tier explicitly. They can tune HA, disk size, retention, maintenance/backup windows, additional PostgreSQL flags, labels, databases and IAM principals. The edition and security baseline are deliberately not switches. Engine support, tier/region compatibility and flag validity are also checked by the Cloud SQL API; major-version upgrades and restarts need a reviewed maintenance plan.

## Prerequisites

- A real project with billing and sufficient quota, and the existing named VPC/PSA allocation. Network routing and firewall policy must allow workloads to reach the private instance. The module never modifies network-team resources.
- Application Default Credentials for the deployment identity, with Cloud SQL administration, Service Usage service-enablement permissions, and project IAM read/write permissions if principals are supplied. Shared VPC may require host-project permissions for Cloud SQL service agents; arrange those with the network team.
- Workloads need ADC for their registered Google identity. On GKE use Workload Identity Federation with Google service-account impersonation; register that Google service account, not a Kubernetes service-account name. On Compute Engine use an attached Google service account and suitable OAuth scopes (`cloud-platform`), never a downloaded key.
- The CLI/provider can validate a plan without confirming that a named project/network exists. Replace the illustrative values in `minimal.tfvars` with real project/network identifiers before applying.

## Run

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

`minimal.tfvars` supplies all six required inputs, provisions only the instance and API enablement, and creates no application databases or identities. Its configuration uses the secure defaults, including regional HA; it is not a free-tier deployment.

For an application deployment, add for example:

```hcl
databases = ["orders"]
iam_principals = {
  "dba@example.com"                            = "IAM_USER"
  "orders@app-project.iam.gserviceaccount.com" = "IAM_SERVICE_ACCOUNT"
  "database-readers@example.com"               = "IAM_GROUP"
}
labels = { environment = "prod", team = "dba" }
```

Use real identities. Group members authenticate individually; don't configure a group and the same individual as parallel database users. Group membership/IAM propagation takes time. A service account's PostgreSQL username omits `.gserviceaccount.com`; outputs provide the resulting usernames. Group membership itself is not managed.

### Connect and grant SQL privileges

Run a Cloud SQL Auth Proxy v2 sidecar/local process using the application's ADC identity:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn --address=127.0.0.1 --port=5432 PROJECT:REGION:INSTANCE
```

Connect the application to `127.0.0.1:5432` using its IAM PostgreSQL username and database. Do not expose the proxy listener to other workloads. The connector handles short-lived tokens and the encrypted instance connection; it does not create network reachability. Language connectors must likewise select private IP and IAM authentication.

IAM login permission is **not** SQL authorization. DBAs must bootstrap and maintain PostgreSQL roles, `CONNECT`, schema/object privileges, default privileges, ownership and extensions through their privileged SQL/migration process. This root intentionally uses only the Google provider: it does not require the deployment runner to reach PostgreSQL, manage SQL grants, or store an administrator credential. Provisioning an IAM user alone does not establish application readiness.

## Operations

- Review plans for replacements, disk changes, version upgrades, flag-induced restarts, and database/user removal. Never reduce a disk after automatic growth. Moving a network or region is not a routine in-place operation.
- Alert on instance health, connections, disk growth, failed backups, replication/failover health and audit delivery through your existing monitoring system. This root does not create notification channels or claim to implement an organization's alerting policy.
- Test PITR and backup restores regularly into a separate instance using the DBA recovery runbook. Regional HA is not cross-region disaster recovery. Backup retention is not an independent archival/export strategy; arrange off-instance recovery and any pre-deletion export before teardown.
- Removing a database destroys its data; instance deletion protection does not guard individual databases. Removing IAM users can fail while they own objects; transfer ownership and revoke SQL privileges first. Other inherited IAM/group access must be revoked through its owning policy as well.
- To intentionally destroy an instance, first set `deletion_protection = false` and **apply**, then destroy using the same variable file. This two-step process prevents routine accidental teardown, not malicious administration.

Outputs: instance name, connector connection name, private address, managed database names and IAM database usernames. No secrets are intentionally generated or output, but provider state contains operational metadata: encrypt and tightly restrict state access.
