# Cloud SQL for PostgreSQL — the DBA team's standard module

Every PostgreSQL database we run on Cloud SQL is stood up and managed through
this module. The standards live here, once, so instances stop being
snowflakes; the decisions that are genuinely per-database stay with the DBA
creating the instance.

The module is a root module in each database's workspace. The Google provider
must already be configured (credentials and project) for the project that
owns both the instances and the VPC networks they attach to — the module
inherits it and does not configure providers.

## Three layers of decisions

| Layer | What it covers | Who decides |
| --- | --- | --- |
| Fixed policy | connectivity, transport security, authentication, data safety, backups, observability, labelling | this module — deliberately not variables |
| Environment policy | high availability, point-in-time recovery, insights | module defaults per `environment`, overridable per instance |
| Per-instance decisions | name, region, zone, version, edition, capacity, databases, flags, identities, replicas, encryption, windows | the DBA team, through variables |

### Fixed policy (no variable, no override)

| Decision | Value |
| --- | --- |
| Connectivity | **Private IP only**, on the environment's VPC via the private services access the network team already runs. Public IPv4 is never enabled and there is no `authorized_networks` input at all. `allocated_ip_range` optionally pins the instance to a specific range the network team pre-allocated. |
| Transport | `ssl_mode = "ENCRYPTED_ONLY"` on the primary and every replica — plaintext connections are refused. Client certificates are not managed: identity is enforced at login instead. |
| Authentication | **Google identities only.** `cloudsql.iam_authentication` is merged into the flags and cannot be turned off, and the module never creates a password-based (`BUILT_IN`) user. Every login — engineer or workload — maps to a Google identity the security team audits. |
| IAM grants | For every listed identity the module grants `roles/cloudsql.instanceUser` (the `cloudsql.instances.login` permission IAM database logins need) and `roles/cloudsql.client` (what the Cloud SQL connectors / auth proxy use to discover the instance), as non-authoritative member bindings that coexist with central IAM. `manage_iam_grants = false` hands them back to a central team. |
| Data safety | Cloud SQL deletion protection plus the Terraform destroy guard on every instance; databases are created with `deletion_policy = "ABANDON"` so removing one from configuration forgets it without dropping data. |
| Backups | Automated backups always enabled; the window, retention and PITR follow policy and variables. |
| Observability | Query Insights with client address and application tags recorded, query string length 1024. |
| Labelling | `environment` and `managed_by = "opentofu"` on every instance, merged under caller-provided labels. |
| Activation | `ALWAYS`. |

### Environment policy (defaults, overridable per instance)

| Standard | dev | staging | prod | Override variable |
| --- | --- | --- | --- | --- |
| `availability_type` | ZONAL | REGIONAL | REGIONAL | `availability_type` |
| Point-in-time recovery | off | on | on | `point_in_time_recovery_enabled` |
| Query Insights | on | on | on | `query_insights_enabled` |

## Prerequisites

1. **Private services access** on the target network — owned by the network
   team, already done on `apps-dev`, `apps-staging` and `apps-prod`. Pass the
   network self link in `network`.
2. **Provider configuration** for the project that owns the networks; the
   module inherits it (`project` is null by default).
3. **Identities** — engineers and workloads already have Google identities;
   pass the emails in `iam_users` / `iam_service_accounts`.
4. **CMEK only**: grant the instance's Cloud SQL service account
   (`service_account_email_address` output)
   `roles/cloudkms.cryptoKeyEncrypterDecrypter` on the key before applying
   with `kms_key_name`.

## Usage

Dev — identical to `minimal.tfvars`:

```hcl
name        = "apps-db"
region      = "us-central1"
environment = "dev"
tier        = "db-custom-2-7680"
network     = "projects/example-project/global/networks/apps-dev"
```

Production — see `examples/prod.tfvars` for databases, IAM users and service
accounts, cross-region read replicas, flags, CMEK and a custom maintenance
window.

**Connecting from GKE / Compute Engine:** run the Cloud SQL connector (or the
auth proxy as a sidecar) with Workload Identity, pass it the
`instance_connection_name` output, and list the workload's service account in
`iam_service_accounts`. **Connecting with psql:** use the
`private_ip_address` over TLS (the server CA is in `server_ca_certificate`),
log in as your email without the `@domain`, and use an OAuth access token
(`gcloud auth print-access-token`) as the password.

## Runbooks

**Decommissioning an instance** — deletion is never a side effect of a config
edit:

1. Set `deletion_protection = false` in the instance's tfvars and apply
   (this disables both the Cloud SQL flag and the Terraform guard).
2. Destroy the workspace, or delete the instance out-of-band after removing
   the configuration.

**Dropping a database** — removing it from `databases` only makes Terraform
forget it. Drop it deliberately, then remove the entry:

```sh
gcloud sql databases delete <db> --instance <instance>
```

**In-database privileges** — `GRANT` statements are the DBA team's SQL
migrations, run through the normal pipeline. The module provisions the login
identities; authorisation inside PostgreSQL stays with the database code.

**Maintenance** — `REGIONAL` availability fails over automatically. The
maintenance window defaults to Sunday 07:00 UTC on the stable track.

## Read replicas

`read_replicas` maps a replica instance name to a tier, with optional
`region` (for cross-region replicas) and disk overrides. Replicas inherit
the network, TLS mode, flags (including IAM authentication), edition and
deletion policy; the primary's connection details are in the outputs.

## What the module deliberately does not do

- Networks, peerings, or allocated ranges — the network team's, and already
  in place.
- Provider configuration or projects — inherited from the workspace.
- Password-based database users — they don't exist here on purpose.
- In-database privileges — owned by the DBAs' SQL migrations.
- KMS keys or their IAM bindings — the module only points the instance at
  `kms_key_name`.
