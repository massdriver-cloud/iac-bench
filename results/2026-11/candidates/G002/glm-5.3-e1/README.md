# Cloud SQL PostgreSQL — the DBA team's standard module

This is the one way PostgreSQL instances get stood up on Cloud SQL. It exists
because instances clicked together in the console are all configured slightly
differently and nobody can say with confidence how any of them is set up.
The module splits the decisions the way the DBA team actually works:

* **The standard** — decisions that should be the same on every instance —
  is decided once, here, and is not negotiable per instance.
* **The per-instance decisions** — the things that are genuinely the DBA
  team's to make (sizing, databases, flags, who gets access) — are inputs.

## The standard

| Decision | Value | Why |
| --- | --- | --- |
| Connectivity | Private IP in the environment VPC only (`apps-dev`, `apps-staging`, `apps-prod`) via the private services access the network team already provisioned | The workloads (GKE, Compute Engine) live in those networks. Public IPv4 and authorized networks are **not supported** by this module at all — reachability is the VPC, full stop. |
| Transport security | `ssl_mode = ENCRYPTED_ONLY` | Unencrypted client connections are rejected. |
| Authentication | Cloud SQL IAM database authentication only. The `cloudsql.iam_authentication` flag is pinned `on` and cannot be overridden. | Every login is a Google identity, which is what the security team audits. The module never sets a password — including for the built-in `postgres` user — so password logins simply do not exist unless someone creates one out-of-band. |
| Authorization | Every principal in `iam_database_users` / `iam_database_groups` / `iam_service_accounts` gets `roles/cloudsql.instanceUser` and `roles/cloudsql.client` at project level, plus its Cloud SQL IAM database user entry | `instanceUser` carries the `cloudsql.instances.login` permission IAM auth checks; `client` lets the Cloud SQL Auth Proxy / language connectors discover the instance. Both roles for every identity, no exceptions. |
| Recovery | Automated backups always on, daily from `06:00` UTC, 7 backups retained, point-in-time recovery on | Backups are a fleet posture, not a per-instance choice. Retention and window are overridable; PITR is on unless an instance is explicitly declared disposable. |
| Availability | `REGIONAL` HA, activation `ALWAYS` | Automatic failover by default. `ZONAL` is allowed for throwaway instances. |
| Storage | SSD, auto-resize on, no cap by default | Disk-full is an outage; auto-resize is availability-first. Set `disk_autoresize_limit` if you want a hard cost guardrail. |
| Observability | Query Insights on, 1024-char query strings | Slow-query telemetry without having to remember to ask for it. |
| Maintenance | Sunday 03:00 UTC, `stable` update track | A predictable, low-traffic window; stable channel everywhere. |
| Safety | Deletion protection on | `terraform destroy` refuses while enabled; destroying an instance is a deliberate, two-step decision. |
| Encryption at rest | Google-managed key by default; optional CMEK via `kms_key_name` | Cloud SQL encrypts everything at rest regardless; CMEK is there when the security team mandates it. |
| PostgreSQL version | `POSTGRES_16` | Bumped deliberately and fleet-wide. Per-instance overrides are allowed but fragment the fleet. |

## What the DBA team decides per instance

`project`, `name`, `region`, `tier`, disk sizing, `databases`, PostgreSQL
`database_flags`, read replicas, who gets access (`iam_database_users`,
`iam_database_groups`, `iam_service_accounts`), `labels`, and — where an
instance genuinely differs — overrides for the defaulted standard decisions
(`availability_type`, `edition`, maintenance window, backup retention and
window, PITR off for disposables, `allocated_ip_range`, CMEK key).

Schema objects *inside* the databases are not managed here; they belong to
the owning application's migration tooling.

## How access works

1. List the identities in `iam_database_users` (engineers),
   `iam_database_groups` (teams — members authenticate as themselves, the
   group carries the grant) and `iam_service_accounts` (GKE workloads,
   Compute Engine VMs).
2. The module creates a `CLOUD_IAM_USER` / `CLOUD_IAM_GROUP` /
   `CLOUD_IAM_SERVICE_ACCOUNT` entry on the instance for each, and grants
   the two project-level roles.
3. Workloads connect with the Cloud SQL Auth Proxy or language connectors
   over the private IP, authenticated by their service account. People
   connect with `psql` using their email as the username and an OAuth access
   token as the password (the proxy and connectors handle the token
   exchange).

Because every login maps to a Google identity, the security team's audit
trail is the identity, not a shared database password. The `iam_principals`
output is exactly the list that gets audited.

## Usage

Minimal (this is what `minimal.tfvars` contains):

```hcl
project = "apps-project"
name    = "apps-dev-pg"
region  = "us-central1"
tier    = "db-custom-2-8192"
network = "apps-dev" # or a self link: projects/<project>/global/networks/apps-dev
```

Everything else above comes along for free. A fuller example:

```hcl
project = "apps-project"
name    = "apps-prod-pg"
region  = "europe-west4"
tier    = "db-custom-8-30720"
network = "apps-prod"

databases = {
  orders    = {}
  analytics = { collation = "en_US.UTF8" }
}

database_flags = {
  max_connections            = "200"
  log_min_duration_statement = "1000"
}

read_replicas = {
  "apps-prod-pg-rr-euw1" = { region = "europe-west1" }
  "apps-prod-pg-rr-euw4" = { tier = "db-custom-4-15360" }
}

iam_database_users       = ["alice@corp.example", "bob@corp.example"]
iam_database_groups      = ["dbas@corp.example"]
iam_service_accounts     = ["orders-gke@apps-project.iam.gserviceaccount.com"]

kms_key_name            = "projects/apps-project/locations/europe-west4/keyRings/dba/cryptoKeys/apps-prod-pg"
backup_retention_count  = 30
maintenance_window      = { day = "SATURDAY", hour = 5, update_track = "stable" }
labels                  = { environment = "apps-prod", team = "dba" }
```

`network` may be a bare network name (resolved in `project`) or the network's
self link. Private services access on that network is the network team's
side and is assumed to exist.

## Inputs

| Name | Type | Default | Notes |
| --- | --- | --- | --- |
| `project` | string | — (required) | Project that owns the instance and the VPC. The module pins the Google provider to it. |
| `name` | string | — (required) | Instance name, validated against Cloud SQL naming rules. |
| `region` | string | — (required) | Instance region. |
| `tier` | string | — (required) | Machine tier, e.g. `db-custom-4-15360`. |
| `network` | string | — (required) | VPC name or self link with private services access. |
| `database_version` | string | `POSTGRES_16` | PostgreSQL 13–17. |
| `edition` | string | `ENTERPRISE` | or `ENTERPRISE_PLUS`. |
| `availability_type` | string | `REGIONAL` | or `ZONAL` for disposables. |
| `deletion_protection` | bool | `true` | |
| `disk_size_gb` | number | `10` | Minimum 10. |
| `disk_autoresize` | bool | `true` | |
| `disk_autoresize_limit` | number | `0` | 0 = no cap. |
| `allocated_ip_range` | string | `null` | Named reserved range, if the network team carved one out. |
| `kms_key_name` | string | `null` | CMEK key self link. |
| `point_in_time_recovery_enabled` | bool | `true` | |
| `backup_retention_count` | number | `7` | 1–365 backups. |
| `backup_start_time` | string | `"06:00"` | HH:MM UTC. |
| `maintenance_window` | object | Sunday 03:00 UTC, `stable` | `day` (name), `hour`, `update_track`. |
| `database_flags` | map(string) | `{}` | Merged over the pinned IAM flag. |
| `databases` | map(object) | `{}` | `charset` / `collation` optional. |
| `read_replicas` | map(object) | `{}` | Per replica: `tier`, `region`, `availability_type`, `disk_size_gb` (all default to the primary's). |
| `iam_database_users` | list(string) | `[]` | Engineer emails. |
| `iam_database_groups` | list(string) | `[]` | Group emails. |
| `iam_service_accounts` | list(string) | `[]` | Workload identity emails. |
| `labels` | map(string) | `{}` | |

## Outputs

`instance_name`, `instance_self_link`, `instance_connection_name` (for the
Auth Proxy / connectors), `private_ip_address` (point your `host` at this),
`instance_service_account_email` (grant it KMS access when using CMEK),
`read_replica_names`, `read_replica_connection_names`,
`read_replica_private_ip_addresses`, `database_names`, and `iam_principals`
(the access list the security team audits).

## Operational notes

* **Destroying an instance** is deliberately two steps: set
  `deletion_protection = false`, apply, then destroy. Dropping the databases
  and instance drops their data; the backups survive per retention.
* **Read replicas** inherit the primary's flags, backups and PITR; they get
  the same private-IP-only, TLS-only connectivity.
* **CMEK**: the key must live in the instance's region, and the instance's
  service account (see the `instance_service_account_email` output) needs
  `roles/cloudkms.cryptoKeyEncrypterDecrypter` on it — grant that outside
  this module, alongside the key.
* **Provider pinning**: `hashicorp/google ~> 6.0` (developed against
  6.50.0). The module pins the provider's `project` to `var.project` so that
  resources without a `project` argument of their own (like
  `google_sql_database_instance`) deterministically land in the DBA
  project — the same one the provider is configured for.
