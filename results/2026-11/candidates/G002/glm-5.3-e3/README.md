# Cloud SQL for PostgreSQL — the DBA team's standard module

One use of this module is one Cloud SQL for PostgreSQL instance, together with the
databases and the database users that belong to it. It exists so that "how is this
database set up?" has exactly one answer across the fleet, and so that the only
decisions a DBA makes per instance are the ones that genuinely differ between
instances.

It is a root module: the instance's decisions live in a tfvars file next to it and
it is applied directly. Google credentials come from the environment; the project
comes from `var.project`.

## What it creates

| Resource | Count | |
|---|---|---|
| `google_sql_database_instance` | 1 | the PostgreSQL instance |
| `google_sql_database` | one per entry of `databases` | plain databases, default template |
| `google_sql_user` | one per entry of `iam_users` | IAM database users |

## What the module decides, identically everywhere

These are not variables. If one of them ever has to change, it changes here, once,
for every instance at the next apply — which is the point.

| Standard | Rationale |
|---|---|
| **Private IP only.** No public IP, and no `authorized_networks` block exists to fill in. | Everything that connects runs on GKE or Compute Engine inside the `apps-*` networks. The instance gets an address on the network you name, via the private services access the network team already provisioned. Nothing outside those networks can reach it, so there is no CIDR list to maintain and no accidental exposure. |
| **IAM database authentication, always on** (`cloudsql.iam_authentication = on`). | Every engineer and every workload already has a Google identity, and the security team audits database access by identity. Nobody invents a database user with a password; there is no password in the state, no password to rotate, and no credential to leak. |
| **No `root_user`, no `postgres` password.** | See above. The `postgres` account simply cannot log in. Break-glass means setting a password out of band with `gcloud sql users set-password`, which is an incident, not a Tuesday. |
| **TLS enforced** (`ssl_mode = ENCRYPTED_ONLY`). | Traffic inside the VPC is still traffic. Clients connect with `sslmode=require`; the Cloud SQL connectors do it by default. |
| **Automated backups and point-in-time recovery, always on.** | A database without a restore path is not a database. The window and the retention periods are yours to choose; whether they exist is not. |
| **Storage auto-resize on.** | `disk_size_gb` is a floor, not a ceiling. `disk_autoresize_limit` is the ceiling, if you want one. |
| **Deletion protection on.** | Destroying an instance requires an explicit opt-out in the configuration *and* clearing the flag in Cloud SQL. Databases should be hard to lose. |
| **Query Insights on, with client addresses recorded.** | When something is slow at 3am, the answer should be a query away, for every instance, including the one nobody thought needed monitoring. |
| **Instance always on** (`activation_policy = ALWAYS`). | A database that is suspended is a database that is down. |
| **A weekly maintenance window.** | Cloud SQL applies minor version updates on a schedule you choose rather than one it chooses. Defaults to Sunday 07:00. |
| **Standard labels**: `environment` (from the variable) and `managed_by = opentofu`. | Cost, inventory and access reporting can rely on them. User labels merge in; the standard labels win. |
| **Data at rest encrypted**, Google-managed by default, your Cloud KMS key if you pass `kms_key_name`. | Same protections everywhere; stronger where the DBA asks for it. |

## What the DBA decides

**Required, no defaults** — these are real decisions, made consciously, per instance:

| Variable | |
|---|---|
| `name` | instance name, unique in the project |
| `project` | the project that owns the `apps-*` networks and hosts the instance |
| `environment` | `dev`, `staging`, `prod`, … (label, and context for audits) |
| `region` | where the instance lives |
| `network` | which `apps-*` network it is reachable from — its name, or a self link |
| `database_version` | the PostgreSQL major version; never defaulted, never silently upgraded |
| `tier` | the machine type, e.g. `db-custom-4-16384` |

**Optional, with a standard default:**

| Variable | Default | |
|---|---|---|
| `zone` | `null` | preferred zone, must be inside `region` |
| `edition` | `ENTERPRISE` | `ENTERPRISE_PLUS` if you want it (it rejects custom flags) |
| `availability_type` | `REGIONAL` | synchronous standby in a second zone, automatic failover |
| `disk_size_gb` | `100` | initial storage, auto-resizes upward |
| `disk_type` | `PD_SSD` | or `PD_BALANCED` / `PD_HDD` |
| `disk_autoresize_limit` | `0` (unlimited) | storage ceiling |
| `backup_start_time` | `04:00` | daily backup window |
| `backup_retention_days` | `30` | automated backup retention |
| `transaction_log_retention_days` | `7` | WAL retention, i.e. the point-in-time recovery window |
| `maintenance_window` | Sunday 07:00, `stable` track | day, hour, update track |
| `query_string_length` | `1024` | Query Insights text length |
| `record_client_address` | `true` | client IP/port in Query Insights |
| `deletion_protection` | `true` | see the standards table |
| `require_ssl` | `true` | see the standards table |
| `allocated_ip_range` | `null` | a specific allocated range, if the network team reserved one |
| `kms_key_name` | `null` | CMEK, must be in the instance's region |
| `databases` | `[]` | databases to create |
| `iam_users` | `{}` | Google identities allowed to log in |
| `database_flags` | `{}` | extra PostgreSQL server parameters |
| `labels` | `{}` | extra labels, merged under the standard ones |

Anything finer-grained than a database *name* — encodings, extensions, roles and
`GRANT`s inside the database — is deliberately not modelled here. That is SQL, and
a DBA applies it with their own identity, where it is visible in the database's own
audit log rather than in infrastructure state.

## Deliberately not in this module

- **Private services access** on the `apps-*` networks. Owned by the network team,
  already in place, and nothing about an instance should recreate it.
- **`roles/cloudsql.instanceUser`** for connecting identities. That is a project IAM
  grant, so it belongs to the security team, not to a database module. Registering an
  identity on the instance (what `iam_users` does) is necessary but not sufficient.
- **Read replicas and cross-region DR.** Worth doing, but they are separate
  decisions with separate failure modes; they will get their own pass, on top of
  this module, rather than being bolted on here half-thought-through.

## Prerequisites

1. **Private services access** on the network you pass, i.e. a VPC peering to the
   Cloud SQL service. The network team owns this and has already set it up on
   `apps-dev`, `apps-staging` and `apps-prod`.
2. The **Cloud SQL Admin API** enabled in `project`.
3. Identities that need to connect hold **`roles/cloudsql.instanceUser`** on the
   project (see above).
4. For CMEK: a key in the instance's region that the project's Cloud SQL service
   account may use.

## Usage

Each instance is one tfvars file in this directory:

```hcl
# orders.tfvars
name             = "orders"
project          = "acme-apps"
environment      = "staging"
region           = "us-central1"
network          = "apps-staging"
database_version = "POSTGRES_16"
tier             = "db-custom-4-16384"

databases = ["orders"]

iam_users = {
  "alice@example.com"                            = {}
  "orders-api@acme-apps.iam.gserviceaccount.com" = { type = "CLOUD_IAM_SERVICE_ACCOUNT" }
}

database_flags = {
  "max_connections" = "400"
}
```

```
tofu init
tofu plan  -var-file=orders.tfvars
tofu apply -var-file=orders.tfvars
```

`minimal.tfvars` is the smallest instance of the module; `example.tfvars` shows a
fully-decided one.

## Connecting

From a workload in the same VPC, the instance is a plain PostgreSQL server with a
private address — use the `private_ip_address` and `connection_name` outputs.

- **Applications**: connect to `private_ip_address:5432` with `sslmode=require`,
  or run the Cloud SQL connectors / Auth Proxy, which do TLS for you. With
  `--auto-iam-authn` (or `auto-iam-authn` in the connector config) the token is
  fetched too, using the workload's own identity — no secret in the deployment.
- **People**: `gcloud sql generate-login-token` mints a short-lived token, which
  you present as the password:
  `psql "host=<private_ip_address> dbname=orders user=alice@example.com sslmode=require"`.
- Grant database privileges the ordinary way (`GRANT ...`), and give an IAM
  identity administrative reach by granting it the `cloudsqlsuperuser` database
  role.

Because every login is an IAM login, the security team can reconcile "who can
reach this database" with "who is this identity" — from `iam_users` here, from the
project's IAM bindings, and from the instance's own logs.

## Outputs

| Output | |
|---|---|
| `instance_name` | the instance's name |
| `instance_self_link` | the instance's self link |
| `connection_name` | `<project>:<region>:<name>`, for the Auth Proxy and connectors |
| `private_ip_address` | the address to connect to from inside the VPC |
| `databases` | the databases the module created |
| `iam_users` | the identities registered on the instance, email → user type |
