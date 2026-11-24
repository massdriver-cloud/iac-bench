# Aurora PostgreSQL — the platform team's production database module

One `tofu apply` gives a service a **multi-region Aurora PostgreSQL database**:
a primary cluster in one region and a continuously replicated warm standby in
a second, wrapped in everything a production database in this platform needs —
encryption with a rotating customer-managed key, enforced TLS, pgAudit piped
to CloudWatch, IAM authentication for EKS, point-in-time recovery, and
private networking built on the network team's existing database subnets.

It exists because a regional outage once took checkout down for most of an
afternoon. The bar the business set — **lose a region, be serving from the
other one within minutes, having lost at most a few seconds of writes** — is
what an Aurora global database delivers: storage-level cross-region
replication that typically lags well under a second, and a warm standby that
takes over in about a minute.

## Using it

A service team fills in the three things only they know and trusts the module
for everything else:

```hcl
# minimal.tfvars — the smallest valid instantiation
service_name   = "checkout"      # their service
environment    = "staging"       # staging | prod — selects the apps-<env> VPCs
instance_class = "db.t4g.medium" # sizing is the service's call
```

```sh
tofu init
tofu plan  -var-file=minimal.tfvars
tofu apply -var-file=minimal.tfvars
```

For a production service, add the handful of knobs that are genuinely
service-level decisions:

```hcl
service_name             = "checkout"
environment              = "prod"
instance_class           = "db.r7g.large"
secondary_instance_count = 2            # fail over at full capacity
backup_retention_period  = 35           # longest retention window
```

Every other input has a deliberate default; see `variables.tf` for the full
list with explanations.

## What it builds

```
                Aurora PostgreSQL global database
            (storage-level replication, typically < 1 s lag)
   ┌──────────────────────────────┬──────────────────────────────┐
   │ primary region (us-east-1)    │ DR region (us-west-2)         │
   │                              │                              │
   │  apps-<env> VPC              │  apps-<env> VPC              │
   │   └ tier=database subnets    │   └ tier=database subnets    │
   │                              │                              │
   │  <svc>-<env>-primary         │  <svc>-<env>-secondary       │
   │    writer endpoint           │    reader endpoint           │
   │    reader endpoint           │    warm-standby instances    │
   │    2 instances (default)     │    1 instance (default, ≥1)  │
   │    CMK-encrypted storage     │    encrypted, identical      │
   │    PITR (14 d default)       │      parameter group         │
   │    pgAudit → CloudWatch      │    pgAudit → CloudWatch      │
   └──────────────────────────────┴──────────────────────────────┘
```

Both clusters share one Aurora global database. The primary serves reads and
writes; the DR cluster serves local reads in its region and stands ready to
be promoted. Replication runs over the AWS backbone — no VPC peering,
Transit Gateway, or customer-managed egress is involved.

## How the DR requirement is met

| Requirement | How |
|---|---|
| Region fails → serving again **within minutes** | The DR region runs real Aurora instances at all times (a warm standby, not a blueprint). Promotion is a metadata operation — typically about a minute — not a restore-from-snapshot (hours). |
| Lose **at most a few seconds** of writes | Aurora global replication operates at the storage layer with typical lag well under one second; on promotion the DR cluster contains everything the primary had committed. |
| No single-region database for checkout-class services | The module *always* builds the global pair — there is no "single region" mode to accidentally pick. |

## Networking

* **No network resources are created for the database tier.** The module
  discovers the network team's VPC in each region by its `Name` tag
  (`apps-staging` / `apps-prod`) and its private database subnets by the
  `tier = database` tag, then builds the DB subnet groups from them. Pass
  `primary_vpc_id` / `secondary_vpc_id` / `vpc_name` to target a VPC that
  doesn't follow the convention.
* A per-region security group allows PostgreSQL **only from the local
  region's apps VPC CIDR** (plus any `allowed_cidr_blocks`). The subnets are
  private, the group has no egress rules, and cross-region replication never
  traverses them.
* The module fails fast at plan time if the discovered database subnets
  don't span at least two availability zones (RDS requires it) — with a
  message pointing at the network team's tag convention, not an opaque AWS
  error at the end of a long apply.

## Security posture (customer and payment data)

* **Encryption at rest**: storage is encrypted everywhere (`storage_encrypted`
  on the global cluster enforces it across members), with a dedicated
  customer-managed KMS key — annual rotation on — covering the primary
  cluster's storage and the master-user secret. Aurora storage keys are
  regional by nature, so DR-region storage is encrypted with the AWS-managed
  RDS key for that region.
* **Encryption in transit**: `rds.force_ssl = 1` — clients that don't
  negotiate TLS are refused outright.
* **Audit logging**: pgAudit is preloaded and configured (statement classes
  via `pgaudit_log_classes`) and both clusters export `postgresql` + `audit`
  logs to CloudWatch groups the module manages with explicit retention
  (`log_retention_in_days`, default 90 days — RDS's own auto-created groups
  never expire).
* **Credentials**: the master password is generated, stored, and rotated by
  RDS in Secrets Manager. It never appears in OpenTofu state, plans, or CI
  logs. The master account is break-glass only.
* **Access**: IAM database authentication is enabled by default so services
  connect through their EKS IAM roles — no shared passwords anywhere.
* **Recovery**: point-in-time recovery with a configurable retention window
  (default 14 days, max 35). Remember that corruption replicates too, so PITR
  is the recovery path of record.
* **Protection**: deletion protection is on automatically in `prod`
  (overridable), clusters are tagged `DataClassification = confidential`, and
  snapshots inherit tags.

## Connecting from EKS (IAM)

The module's outputs exist to make this wiring short. In the database, create
a role per service (once, via your migration tooling):

```sql
CREATE USER checkout_app;
GRANT rds_iam TO checkout_app;
-- plus your ordinary schema/connect grants
```

Then grant that service's IRSA role permission to mint a token:

```json
{
  "Effect": "Allow",
  "Action": "rds-db:connect",
  "Resource": [
    "arn:aws:rds-db:us-east-1:123456789012:dbuser:${primary_cluster_resource_id}/checkout_app",
    "arn:aws:rds-db:us-west-2:123456789012:dbuser:${secondary_cluster_resource_id}/checkout_app"
  ]
}
```

Both `cluster_resource_id` outputs are in the module's outputs; generate the
token with the AWS SDK's `generate_db_auth_token` and connect over TLS to
`primary_writer_endpoint` (or `primary_reader_endpoint` for read-only
traffic). The `master_user_secret_arn` output locates the break-glass
credentials in Secrets Manager.

## Failover runbook

The commands below work with the module's outputs as-is.

### Planned failover (e.g. before regional maintenance)

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier $(tofu output -raw global_cluster_identifier) \
  --target-db-cluster-identifier $(tofu output -raw secondary_cluster_arn) \
  --region $(tofu output -raw secondary_region)
```

This is a managed operation: roles swap, the global database and its members
stay intact, and OpenTofu sees no drift (the module's clusters are tracked by
region, not by role). Services reconnect to the writer endpoint of the region
that is now primary — point them at `primary_writer_endpoint` /
`secondary_writer_endpoint` via your usual config mechanism. Fail back the
same way in reverse when the maintenance window closes.

### Unplanned failover (primary region down)

When the primary region is unhealthy, managed failover can't be used against
it — isolate and promote the DR cluster instead:

```sh
aws rds remove-from-global-cluster \
  --db-cluster-identifier $(tofu output -raw secondary_cluster_arn) \
  --region $(tofu output -raw secondary_region)
```

Within minutes the DR cluster is a standalone writable cluster holding
everything the primary had committed (replication lag at the moment of loss,
typically < 1 s). Point services at `secondary_writer_endpoint`.

### Returning to steady state

A cluster detached from its global database is standalone; global-cluster
membership is established at creation, so recovery is: rebuild a secondary in
the recovered region with this module (swap `primary_region` /
`secondary_region`, re-import the promoted cluster into state, and clean up
the orphaned resources) — a platform-team exercise, ideally rehearsed during
a game day before it is ever done under pressure. Managed (planned) failover
in both directions should be your normal operating mode; reserve the
detach-and-promote path for a genuinely lost region.

## Day-2 operations

* **Upgrades**: bump `engine_version` — the module moves the global cluster
  and then each regional cluster through the new version in order, keeping
  both members on the same version. Automatic minor-version upgrades are
  disabled on purpose so the pair never drifts apart; run them deliberately.
* **Scaling**: change `instance_class` (applies to both regions) or the
  instance counts. If a service must fail over without degrading, set
  `secondary_instance_count` to match `instance_count`.
* **Teardown**: destroy removes the DR member first, then the primary, then
  the global cluster — the order Aurora requires. Staging tears down cleanly
  by design; prod will refuse until `deletion_protection` is consciously
  turned off. `skip_final_snapshot = false` leaves a final snapshot of the
  primary (the DR member only ever held a replica of that data).

## Known trade-offs (deliberate)

* **DR-region storage key**: Aurora storage encryption keys are regional; the
  DR member's storage is encrypted with the AWS-managed RDS key in its region
  rather than the primary's CMK (which cannot cross regions).
* **Audit scope**: the default pgAudit classes capture writes, DDL, role
  changes, and utility statements — not reads. Add `"read"` to
  `pgaudit_log_classes` when an auditor requires cardholder-access logging,
  accepting a large increase in log volume and cost.
* **Cluster identifiers** (`-primary` / `-secondary`) describe the initial
  provisioning roles and stay stable through failovers — endpoints and log
  groups are keyed off them, so nothing churns in an incident.
* **Write forwarding is not used**: services fail over to the promoted
  region's endpoint rather than accepting cross-region write latency; one
  code path, predictable behavior.
