# Standard PostgreSQL on Cloud SQL

Standalone OpenTofu root module; creates one PostgreSQL primary, optional databases and IAM database principals. It does not call external modules, create networks, change private services access, or generate/store database passwords.

## Contract and decisions

| Standard | Rationale |
| --- | --- |
| Private IP only on existing `apps-dev`, `apps-staging`, or `apps-prod` | No public endpoint or authorized public networks. `network_project_id` supports a Shared VPC host project. |
| Cloud SQL Auth Proxy / language connector required, TLS required | Connectors authenticate and encrypt connections. They must use private IP; a connector does **not** provide a route into the VPC. |
| IAM database authentication enabled and non-overridable | Each human or workload logs in as its Google identity; no shared application passwords. |
| Additive, instance-conditioned `cloudsql.client` and `cloudsql.instanceUser` grants | Principals can connect and IAM-login to this instance, not every instance in the project. Existing IAM policies are not replaced. |
| Enterprise edition, SSD, automatic uncapped storage growth | Predictable supported baseline. Monitor cost/capacity. Disk size is initial capacity only: subsequent size drift is ignored to avoid shrinking after auto-growth. Use an explicit operational change for manual growth. |
| Always on; REGIONAL HA by default, required for prod | Zonal instances are available for lower-cost non-production deployments. Shared-core tiers cannot be used with HA; select a dedicated tier for REGIONAL. |
| Daily backups, 14 retained by default, seven days of PITR logs | Backups/PITR cannot be disabled. Backup retention can be increased or reduced to at least seven. Backup location uses Cloud SQL's regional default. HA is not a backup or regional disaster recovery strategy. |
| Weekly stable-track maintenance window | DBAs choose the UTC window; restarts and engine upgrades still require planning. |
| Both API and OpenTofu deletion protection enabled | Intentional destruction requires first applying `deletion_protection = false`. |

DBAs explicitly select project, region, PostgreSQL major version and machine tier. They own database names/locale, tuning flags, IAM principals, availability (within the production policy), capacity, retention and maintenance timing. No sample users or databases are silently created. Labels include enforced environment and management labels.

## Prerequisites

* An existing project with Cloud SQL Admin API enabled and billing configured. Cloud Identity group authentication also needs the relevant organization/group setup. API and network lifecycle remain with platform/network teams.
* Existing named VPC and working private services access with enough allocated addresses. For Shared VPC, configure service project attachment and Cloud SQL service-agent/host-network permissions externally.
* Application/engineer network reachability to the VPC (GKE/VM private routing, VPN or equivalent), including connector control-plane/API egress. No routing, firewall, NAT, VPN, workload identity or service-account impersonation resources are managed here.
* Runner credentials from Application Default Credentials, with permissions to manage Cloud SQL resources and conditional project IAM bindings (typically Cloud SQL Admin plus Project IAM Admin; use a tailored deployment role in production). This module does not grant those administrative privileges.
* Use a protected, encrypted remote state backend with appropriate locking/access policy. Backend configuration is deliberately deployment-specific; the module creates no secrets, but state still contains infrastructure and identity metadata.

## Run

`minimal.tfvars` is a literal, small zonal dev example without application databases or logins. Its project IDs are illustrative: replace them with actual projects provisioned with the prerequisites before applying. It defaults to deletion protection and still retains backups/PITR. It is not a production sizing recommendation.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

For production, use a separate directory/state/workspace and tfvars with a dedicated tier and `availability_type = "REGIONAL"`. Never switch environments in an existing instance's state as a deployment strategy. Review plans, especially replacement, database deletions, engine upgrades, or identity removals.

Additional tfvars example (alongside the required inputs):

```hcl
databases = {
  orders = {} # UTF8 / en_US.UTF8 by default
}
iam_users            = ["dba@example.com"]
iam_service_accounts = ["orders@app-project.iam.gserviceaccount.com"]
iam_groups           = ["database-operators@example.com"]
database_flags = {
  max_connections = "200"
  log_connections = "on"
  log_disconnections = "on"
}
maintenance_window = { day = 7, hour = 4 }
labels = { team = "dba" }
```

Use canonical email casing. Do not register a group member individually as well: Cloud SQL does not support the same login simultaneously as individual IAM and group-derived IAM. Group membership propagation and first-login user materialization are Cloud SQL/Cloud Identity behavior, not managed PostgreSQL users here.

## Connecting and authorization

For a VM or GKE workload using its own Google service account via ADC/Workload Identity:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn --port 5432 PROJECT:REGION:INSTANCE
psql 'host=127.0.0.1 port=5432 dbname=orders user=orders@app-project.iam sslmode=disable'
```

The local hop is loopback only; the proxy-to-Cloud-SQL hop is authenticated and encrypted. Do not expose the local listener publicly. On GKE use a sidecar or an in-process language connector with private IP and automatic IAM authentication. Engineers use their own ADC identity and full email as database username, from a network location with private reachability. Service account database usernames omit `.gserviceaccount.com`; outputs expose the exact mapping. Automatic IAM authentication refreshes short-lived login tokens; no token/password is written to state.

IAM login does **not** grant SQL object privileges. A DBA must separately bootstrap database ownership, schema/table/sequence grants, default privileges and optional extensions with a controlled SQL migration process. This root deliberately does not require a PostgreSQL provider or a live SQL connection during provisioning. Google-managed built-in administrative roles/users are not removed; this module creates no built-in password accounts. Privileged Cloud SQL administrators remain a trusted boundary and can change authentication outside this module.

## Operations and boundaries

* Standard Cloud SQL platform audit logging is available, but Data Access audit policy, log sinks/retention, alerts and organization-wide auditing belong to the security/observability platform. IAM identities enable attribution; they do not automatically log every SQL statement. DBAs can set logging/pgAudit flags and install/configure extensions separately if SQL-statement auditing is required. Avoid logging sensitive query payloads unintentionally.
* Restore/PITR drills and cross-region DR are separate operational workflows. This module does not restore backups, clone existing instances, create read replicas, or run migrations. It provisions new primaries; import existing resources deliberately rather than assuming automatic adoption.
* Removing a database destroys its contents. Instance deletion protection does not protect individual databases. SQL user removal can fail when that principal owns objects or has dependent grants; transfer ownership/revoke grants before removing it from configuration.
* Conditional IAM grants do not revoke access granted elsewhere. Avoid multiple roots managing an identical principal/role/condition tuple. Instance-specific conditions keep this module's bindings independent between instances.
* To decommission: export/verify retained recovery data, remove SQL dependencies, apply deletion protection off, review and destroy. No promise of retained recovery data after deletion is made; export required archival copies first.
