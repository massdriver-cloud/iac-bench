# aurora-postgresql-global

Production Aurora PostgreSQL for customer-facing services, built to survive the loss of an AWS region.

## What you get

| Concern | Decision |
|---|---|
| Regional failure | **Aurora Global Database**: primary cluster in `primary_region`, full replica in `secondary_region`. Storage-level replication (typically < 1 s lag). Managed failover/switchover promotes the secondary in minutes. |
| AZ failure | Every regional cluster has at least a writer and one reader in different AZs (`instances_per_region`, min 2). |
| Network | Discovers VPC `apps-<environment>` and its subnets tagged `tier = database` in each region. Security group admits TCP/5432 from the VPC CIDR by default, or only from the CIDRs / security groups you list. Instances are never publicly accessible. |
| Encryption | Customer-managed KMS key per region with annual rotation. Encrypts storage, snapshots, Performance Insights and the master secret. TLS is mandatory (`rds.force_ssl = 1`). |
| Credentials | Master password generated and rotated by AWS Secrets Manager — never in state. Applications authenticate with **IAM** (`iam_database_authentication_enabled`); the module emits an IAM policy granting `rds-db:connect` on both clusters for your `application_db_users`. |
| Backups / safety | 35-day automated backups, final snapshot on destroy, deletion protection on the global and regional clusters, tags copied to snapshots. |
| Observability | PostgreSQL logs to CloudWatch, Enhanced Monitoring (15 s), Performance Insights, `pg_stat_statements`, slow-query/DDL/connection logging. Alarms on cross-region replication lag (the RPO), CPU, memory and connections. |

## Minimal usage

```hcl
service_name = "checkout"
environment  = "prod"
```

Everything else has a production-safe default. Commonly overridden:

```hcl
instance_class       = "db.r6g.xlarge"
instances_per_region = 3
allowed_security_group_ids = {
  primary   = ["sg-0123eksnodes"]
  secondary = ["sg-0456eksnodes"]
}
alarm_actions = {
  primary   = ["arn:aws:sns:us-east-1:123456789012:checkout-oncall"]
  secondary = ["arn:aws:sns:us-west-2:123456789012:checkout-oncall"]
}
```

## Connecting from EKS

1. Attach `application_connect_policy_arn` to the service's IRSA / Pod Identity role.
2. Once, using the master secret (`master_user_secret_arn`), create the application role:
   ```sql
   CREATE ROLE app WITH LOGIN;
   GRANT rds_iam TO app;
   GRANT ALL ON DATABASE checkout TO app;
   ```
3. Generate a token (`rds generate-db-auth-token`) and connect with `sslmode=verify-full` to the regional writer/reader endpoint from the `primary` / `secondary` outputs. Services in the secondary region may write to their local endpoint when `enable_global_write_forwarding` is on (set `apg_write_forward.consistency_mode` in the session).

## Failing over

See the `failover_runbook` output. Planned moves use `switchover-global-cluster` (no data loss); a regional outage uses `failover-global-cluster --allow-data-loss`, losing at most the current replication lag (alarmed at `replication_lag_alarm_threshold_ms`). After a failover, swap `primary_region` / `secondary_region` in the tfvars and plan to realign state — the module ignores the attributes AWS rewrites during promotion.

## Upgrades

Minor versions auto-apply in the maintenance window. Major versions are upgraded on the global cluster out-of-band; the module ignores `engine_version` drift for that reason — bump the variable afterwards.
