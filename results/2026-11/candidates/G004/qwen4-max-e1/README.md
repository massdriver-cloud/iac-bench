# Aurora PostgreSQL — production database module (cross-region DR)

Reusable OpenTofu root module for the PostgreSQL databases behind customer-facing
services. One call stands up a production-grade **Aurora PostgreSQL Global
Database** spanning two US regions.

## How this meets the business bar

> "If an AWS region fails, the database must be serving again from another
> region within minutes, having lost no more than a few seconds of writes."

* **Aurora Global Database** replicates at the storage layer to a secondary
  cluster in a second region (default `us-east-1` → `us-west-2`), typically
  **< 1 second behind** (RPO ≈ seconds, not minutes like logical/binlog replicas).
* On a regional outage, a **global failover (detach-and-promote)** makes the
  secondary cluster a standalone writer in **~1 minute** (RTO). The DR region
  already runs at least one instance, so there is nothing to provision during
  an incident.
* A CloudWatch alarm on `AuroraGlobalDBRPOLag` fires if replication ever falls
  more than 10 s behind, so operators know *before* the RPO bar is at risk.
* In-region HA comes free: the primary cluster always has ≥ 2 instances across
  AZs; an instance/AZ failure promotes a reader in ~30 s without touching DR.

## What the module owns (defaults you should not have to think about)

| Concern | Decision |
|---|---|
| Engine | Aurora PostgreSQL 16.4, provisioned `db.r6g.large` (tunable) |
| Topology | Global cluster: 2 instances primary region, 1 in DR region (tunable) |
| Encryption at rest | Customer-managed KMS keys in **each** region, annual rotation, 30-day deletion window |
| Encryption in transit | `rds.force_ssl = 1` — non-TLS connections are rejected |
| Credentials | Master password generated & managed by RDS in Secrets Manager (never in variables/state inputs). Workloads use **IAM database authentication** |
| Audit | `pgaudit` (DDL + role changes), connection/disconnection logging, PostgreSQL logs exported to CloudWatch |
| Backups | 35-day retention (PITR), tagged snapshots, mandatory final snapshot, deletion protection on clusters and global cluster |
| Network | Discovers the network team's VPC (`Name = apps-<environment>`) and private subnets (`tier = database`) in both regions; DB security group accepts 5432 only from inside the environment VPC; no public access |
| Monitoring | Enhanced Monitoring (60 s), Performance Insights (731-day retention, CMK-encrypted), CPU/memory alarms, global RPO-lag alarm, SNS alert topic per region |

## What callers supply

Only `service` and `environment` are required (see `minimal.tfvars`). Common
per-service overrides: `database_name`, `instance_class`,
`primary_instance_count`, `secondary_instance_count`, `engine_version`,
`primary_region` / `secondary_region`, `iam_database_users`, `alarm_email`,
`tags`.

```hcl
# example: prod checkout database
service              = "checkout"
environment          = "prod"
instance_class       = "db.r6g.xlarge"
secondary_instance_count = 2
alarm_email          = "checkout-oncall@example.com"
```

## Wiring services (EKS / IAM)

1. Attach the output `db_connect_policy_arn` to the service's IRSA role. It
   grants `rds-db:connect` **only** to this database's clusters in both regions,
   only for the users in `iam_database_users` (default `app`).
2. In the database, create the matching user once:
   `CREATE USER app; GRANT rds_iam TO app;` plus the schema grants the service needs.
3. Connect with short-lived IAM tokens (`aws rds generate-db-auth-token`) over
   TLS to `primary_endpoint` (writes) / `primary_reader_endpoint` (reads).
   Services in the DR region read from `secondary_reader_endpoint`.
4. The master secret (`master_user_secret_arn`) is break-glass only — grant it
   to humans/automation narrowly, never to workload roles.

## Failover runbook

**Planned (region evacuation, zero data loss):**
```bash
aws rds switchover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --region us-west-2
```
Switchover waits for replication to catch up (RPO = 0), then flips writer roles.

**Unplanned (primary region down):**
```bash
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --allow-data-loss \
  --region us-west-2
```
Detaches and promotes the secondary in ~1 minute; lost writes are bounded by
replication lag (normally < 1 s — the RPO alarm guards this). Then:

1. Point service write traffic at the promoted cluster's endpoint (the old
   `secondary_reader_endpoint` name now serves writes; update the service's
   DB config / DNS).
2. When the failed region returns, re-establish DR: remove the old primary
   from the global cluster and add it back as the new secondary (or swap
   regions via the module's `primary_region`/`secondary_region` variables and
   re-apply). Do not leave the database single-region.

## Files

* `versions.tf` — providers (primary + `aws.secondary` alias), default tags
* `variables.tf` — caller inputs with production defaults and guardrails
* `data.tf` — account/partition + VPC/subnet discovery in both regions
* `network.tf` — DB subnet groups and security groups (private subnets only)
* `kms.tf` — per-region CMKs for storage, snapshots, PI and the master secret
* `iam.tf` — least-privilege `rds-db:connect` policy + enhanced-monitoring role
* `parameter_groups.tf` — TLS enforcement, pgaudit, session logging
* `primary.tf` — global cluster + primary cluster/instances
* `secondary.tf` — DR cluster/instances
* `monitoring.tf` — SNS topics and CloudWatch alarms (incl. RPO lag)
* `outputs.tf` — endpoints, secret/policy/key ARNs, alert topics
