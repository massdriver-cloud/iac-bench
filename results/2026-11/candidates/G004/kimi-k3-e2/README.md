# Aurora PostgreSQL (global) — standard module for production databases

The platform team's standard for customer-facing production databases. One
Aurora **global database** per service: a writer cluster in the primary
region and a replicated cluster in a second US region, ready to take over.

## Why these decisions

| Requirement | Decision |
| --- | --- |
| Survive a region loss, back in minutes, lose at most seconds of writes | **Aurora global database.** Storage-level replication to the secondary region with sub-second typical lag (RPO of seconds), and *managed switchover* (`switchover-global-cluster`) that promotes the secondary with **zero data loss in about a minute** (RTO of minutes). |
| Services on EKS authenticate via IAM roles | `iam_database_authentication_enabled` on both clusters. Create per-service DB users `WITH rds_iam` and let pods generate auth tokens. The master password is break-glass only: RDS generates it and stores it in Secrets Manager (no password in configuration or state). |
| Customer + payment data | Encryption at rest with per-region **customer-managed KMS keys** (storage, snapshots, Performance Insights, master secret); **TLS enforced** (`rds.force_ssl=1`); connection/DDL audit logging; logs exported to CloudWatch with 365-day retention; deletion protection and final snapshots on. |
| Platform engineers aren't DB specialists | Sensible, overridable defaults everywhere: pg_stat_statements, slow-query log (>1s), lock/temp-file logging, enhanced monitoring, Performance Insights, promotion tiers, backup (14d PITR) and maintenance windows. |
| Network owned by the network team | The module discovers the VPC tagged `Name = apps-<environment>` and subnets tagged `tier = database` in each region. Explicit `*_vpc_id` / `*_database_subnet_ids` overrides exist as an escape hatch. |

## Usage

```hcl
# tfvars for the checkout service, production:
name        = "checkout"
environment = "prod"
```

That is the whole contract. Optional knobs (`instance_class`,
`primary_instance_count`, `engine_version`, `cluster_parameter_group_parameters`, …)
are documented in `variables.tf`.

## Regional recovery runbook

**Planned / primary region degraded** (zero data loss, ~1 minute):

```sh
aws rds switchover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --region <secondary_region>
```

**Primary region down** (may lose the last seconds of unreplicated writes):

```sh
aws rds failover-global-cluster \
  --global-cluster-identifier <global_cluster_identifier> \
  --target-db-cluster-identifier <secondary_cluster_arn> \
  --allow-data-loss \
  --region <secondary_region>
```

Both commands are emitted as module outputs (`switchover_command`,
`failover_command`) with the identifiers filled in. After recovery, point the
service at the secondary cluster's endpoint (now the writer) and rebuild the
failed region at leisure with `terraform apply` after moving
`primary_region`/`secondary_region` around as needed.

## Connecting from EKS (IAM authentication)

```sql
-- once, as the master user (password in Secrets Manager, see output):
CREATE USER app_checkout WITH LOGIN;
GRANT rds_iam TO app_checkout;
```

Pods use an IRSA role allowed `rds-db:connect` on
`<cluster_resource_id>/app_checkout` and connect with a generated auth token.
SSL is required — use the RDS CA bundle and `sslmode=verify-full`.

## Notes

- `primary_region` / `secondary_region` default to `us-east-1` / `us-west-2`
  and must differ.
- The secondary cluster runs at least one warm instance by default so reads
  work cross-region today and switchover is fast.
- Major-version upgrades: bump `engine_version`; the parameter group is named
  per major version and is replaced safely (`create_before_destroy`).
