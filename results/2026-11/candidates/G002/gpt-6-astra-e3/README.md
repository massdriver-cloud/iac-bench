# DBA PostgreSQL baseline

Standalone OpenTofu root module; no remote modules. One Cloud SQL PostgreSQL instance per root/state. Use separate state and tfvars for each instance/environment. Credentials come from Application Default Credentials / workload identity in the environment; no credentials or database passwords are inputs or outputs.

## Decisions owned by this baseline

* **Private-only** IP on an existing custom VPC. No public IP, authorized networks, new VPC, or private services access resources. Supply `apps-dev`, `apps-staging`, or `apps-prod` as appropriate, including the host project for Shared VPC.
* **Google identity access**: IAM database authentication is always enabled. Only IAM users, service accounts and groups are provisioned; there are no application password users or generated secrets. Cloud SQL's built-in `postgres` account still exists; this module does not set its password. Enforce restrictions on out-of-band password-user creation through organization policy/operational controls.
* **Connector-required, encrypted connections**: Cloud SQL Auth Proxy or a supported language connector is mandatory. Use private IP and automatic IAM authentication. This deliberately disallows ordinary direct-IP PostgreSQL sessions, even over TLS.
* **Recoverability**: daily backups, PITR, SSD storage and automatic storage growth are mandatory. Default retention is 14 backups and 7 days of PITR logs. Backups are not a substitute for tested restores or a cross-region DR design.
* Regional HA, stable scheduled maintenance and two layers of instance deletion protection are the defaults. No automatic major-version selection or upgrades.

DBAs choose the major version, region, machine tier, edition, HA versus zonal deployment, storage size/ceiling, backup timing/retention, maintenance window, PostgreSQL tuning flags, application databases and permitted Google identities. IAM authentication cannot be overridden via tuning flags. Validate tier/version/edition combinations against Cloud SQL availability before applying; some changes restart or replace the instance.

## Prerequisites and use

The SQL Admin API must already be enabled in the instance project. The network team must have completed private services access with sufficient IP space in the supplied VPC, including Shared VPC permissions where applicable. This root intentionally does not enable/disable shared project APIs or change network ownership.

The execution identity needs Cloud SQL resource administration and project IAM policy update permissions (for nonempty `iam_principals`), plus permission to use the supplied network. Review least-privilege custom deployment roles for your organization. The runtime identities must already exist; groups require Cloud Identity/Google Workspace membership management outside this module.

`minimal.tfvars` gives literal example identifiers and the smallest set of required inputs. Replace project/network identifiers with your real environment before applying:

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

Use a protected remote state backend configured by your deployment system. The empty default database/identity sets create only the instance and its built-in databases, without granting anyone application access. For a usable application deployment, add for example:

```hcl
databases = ["orders"]
iam_principals = {
  "dba@example.com" = "USER"
  "orders@my-project.iam.gserviceaccount.com" = "SERVICE_ACCOUNT"
  "database-readers@example.com" = "GROUP"
}
labels = { environment = "prod", owner = "dba" }
```

Each identity gets additive `roles/cloudsql.client` and `roles/cloudsql.instanceUser` grants conditioned on this specific instance. Existing broader IAM grants are not revoked by this module. Group members authenticate as themselves for attribution. Do not simultaneously create an individual IAM database user and an IAM group containing that user; Cloud SQL requires migration between these modes. Allow IAM/group propagation time.

For GKE, use Workload Identity Federation with an identity supported by Cloud SQL IAM database authentication (typically an impersonated Google service account). For Compute Engine, use the attached service account and appropriate OAuth scopes, normally `cloud-platform`. Do not download service-account keys. Workloads/proxies must have VPC routing and firewall egress to Cloud SQL's private endpoint (connector TCP 3307) and Google APIs (HTTPS 443); connectors supply authentication/encryption, not a network tunnel into the VPC.

For an engineer running from a VPC-connected host, with their Google identity in `iam_principals`:

```sh
cloud-sql-proxy --private-ip --auto-iam-authn --address 127.0.0.1 --port 5432 PROJECT:REGION:INSTANCE
psql 'host=127.0.0.1 port=5432 dbname=orders user=dba@example.com sslmode=disable'
```

The local loopback proxy connection is distinct from the encrypted proxy-to-Cloud-SQL connection. Do not expose the local proxy listener to other hosts. Service-account PostgreSQL usernames omit `.gserviceaccount.com`; outputs show the configured names.

## Authorization, auditing and lifecycle

IAM connection/login permission is **not PostgreSQL object authorization**. DBAs must bootstrap and manage database ownership, CONNECT, schema/table privileges, default privileges and role membership using their SQL administration workflow. This root uses only the Cloud SQL control plane and never opens a database session; it neither grants blanket database privileges nor installs a PostgreSQL provider. Handle any initial privileged SQL/bootstrap session through an approved DBA process; no administrator password is stored here.

Identity-backed sessions provide attributable PostgreSQL usernames. Security must maintain central Cloud Audit Logs/Data Access policy, log routing and retention at project/organization scope. IAM login alone does not audit every SQL statement. If statement-level auditing is required, DBAs can enable supported pgAudit flags and configure the extension via SQL under their audit policy. This module does not change shared project audit policy or silently enable full query logging, which can expose sensitive data.

To destroy an instance, set `deletion_protection = false` and **apply that change first**, then destroy. Both the provider and API protections default to true. While protection is true, application databases use `ABANDON`: removing one from configuration leaves the database intact but removes it from state (re-import to manage it again). With protection false, database removal deletes data. IAM user removal deletes that database user and this module's IAM grants; PostgreSQL ownership/dependencies may require DBA cleanup first. Removing module grants does not revoke independently granted access.

Storage can grow but cannot shrink. Names, regions and networks have significant replacement/migration constraints; review every plan. Schedule and test recovery separately, including a restore before any destructive change. Backups are not promised to survive instance deletion by this module. Pin the generated provider lock file in version control for reproducible deployments.
