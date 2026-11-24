# Aurora PostgreSQL — production database module

Standard module for the platform team's customer-facing PostgreSQL databases.
It provisions an **Aurora PostgreSQL Global Database** across two US regions so
that a full regional outage is survivable with:

- **RPO ≈ 1 second** — Aurora global physical replication is asynchronous but
  typically lags well under a second.
- **RTO < 1 minute** — the DR region always runs at least one warm reader, so
  an unplanned detach-and-promote completes in well under a minute, plus the
  time to repoint the service's endpoint configuration.

## What the module owns (so service teams don't have to)

| Concern | Decision |
|---|---|
| Topology | Global database; primary `us-east-1`, DR `us-west-2` (overridable, US-only) |
| In-region HA | 2 instances in the primary (writer + hot standby reader) |
| DR readiness | 1+ warm reader in the DR region (mandatory, enforced) |
| Network | Discovers the network team's VPC (`Name = apps-<env>`) and subnets tagged `tier = database` in **both** regions; creates nothing network-owned |
| Access control | Security group allows 5432 only from inside the environment VPC; instances are never publicly accessible; no SG egress |
| Encryption at rest | Per-region customer-managed KMS keys, rotation enabled, 30-day deletion window |
| Encryption in transit | `rds.force_ssl = 1`, modern CA (`rds-ca-rsa2048-g1`) |
| App authentication | IAM database authentication (EKS/IRSA roles); a ready-made `rds-db:connect` policy is output for both regions |
| Admin credentials | RDS-managed master password in Secrets Manager (encrypted with the CMK); break-glass only |
| Backups | 14 days PITR in each region (min 7 enforced), tags copied to snapshots, final snapshot on destroy |
| Accident protection | Deletion protection on the global database and both clusters |
| Audit/observability | PostgreSQL logs to CloudWatch (90-day retention), connection/DDL/slow-statement logging, enhanced monitoring (60 s), Performance Insights (CMK-encrypted) |

## Usage

```hcl
# root module example
service_name = "checkout"
environment  = "prod"
# optional overrides: instance_class, primary_instance_count, engine_version, ...
```

Only `service_name` and `environment` are required. `minimal.tfvars` is the
smallest valid instantiation.

### One-time database bootstrap (as the break-glass admin)

```sql
CREATE USER app;                      -- matches var.app_db_username
GRANT rds_iam TO app;
GRANT CONNECT ON DATABASE app TO app;
-- plus the schema grants your service needs
```

### Application connectivity (EKS)

1. Attach the output `db_connect_policy_arn` to the service's pod IAM role (IRSA).
2. Generate a 15-minute IAM auth token and use it as the password over TLS:
   `aws rds generate-db-auth-token --hostname <endpoint> --port 5432 --region <region> --username app`
3. Connect with `sslmode=verify-full` and the AWS RDS CA bundle.
4. Use `primary_endpoint` for writes, `primary_reader_endpoint` for reads.
   Keep the endpoint in service configuration (e.g. a ConfigMap/secret the
   platform team flips during failover) — do not hardcode it.

## Regional failover runbook

Cross-region failover is intentionally a **human decision**: automated
promotion on transient signals risks split-brain and lost payment writes.

**Planned move (region healthy — zero data loss):**
```bash
aws rds switchover-global-cluster \
  --global-cluster-identifier <service>-<env>-global \
  --target-db-cluster-identifier <arn of DR cluster>
```
Blocks writes until regions are in sync, then swaps roles. Both endpoints
keep their names; the old primary becomes the DR region.

**Unplanned regional outage (RPO ~1 s, RTO < 1 min):**
```bash
# 1. Detach the DR cluster (it becomes a standalone writable cluster)
aws rds remove-from-global-cluster \
  --global-cluster-identifier <service>-<env>-global \
  --db-cluster-identifier <arn of DR cluster> --region <dr-region>
# 2. Ensure a writer is promoted (fast because readers are warm)
aws rds failover-db-cluster --db-cluster-identifier <service>-<env>-dr --region <dr-region>
# 3. Repoint the service's DB endpoint at the DR cluster endpoint output.
```
Accept up to ~1 s of acknowledged-write loss; reconcile payments from the
service's idempotency/journal records if needed.

**After the failed region returns:** do **not** rejoin the old primary as-is
(it may hold divergent writes). Rebuild the DR region from the surviving
cluster (re-apply with the regions swapped, or add a new secondary cluster to
the global database) and resync.

## Notes and guardrails

- `environment` must be `staging` or `prod`; the VPC is selected as `apps-<env>`.
- Both regions must be US regions (data residency); the module enforces this.
- Backup windows in the two regions are staggered (global database requirement).
- Engine upgrades: minor versions auto-apply in the maintenance window;
  major upgrades are disabled by default and should be a deliberate,
  global-database-aware operation.
- Deletion protection defaults to `true`; tearing down a prod database is a
  two-step, intentional act.
