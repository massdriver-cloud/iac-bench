# Aurora PostgreSQL — production database module

Stands up a production-grade **Aurora PostgreSQL Global Database** for one
service: a primary cluster in one US region and a continuously replicated
secondary cluster in another, ready to be promoted within minutes.

## What you get

| Concern | Decision |
|---|---|
| Regional failure | Aurora Global Database; secondary region has running instances and can be promoted in ~1 minute (`aws rds failover-global-cluster`) |
| Data loss bound | `rds.global_db_rpo` is set (default 20 s, the AWS minimum). If lag ever exceeds it, Aurora pauses writes rather than exceed the RPO. Typical lag is < 1 s and is alarmed at 5 s |
| AZ failure | Primary cluster always has ≥ 2 instances across AZs; in-region failover is automatic |
| Encryption | Customer-managed KMS key per region (rotation on), storage + Performance Insights + master secret encrypted, TLS enforced (`rds.force_ssl=1`) |
| Credentials | IAM database authentication for applications (`db_connect_policy_arn` → attach to the EKS pod role). Master password generated and held by RDS in Secrets Manager |
| Audit | pgaudit (DDL + role changes), connection logging, slow-query logging, logs shipped to CloudWatch with retention |
| Backups | 35-day automated backups, final snapshots, tags copied to snapshots, deletion protection on |
| Network | Placed in the network team's `apps-<environment>` VPC on the `tier = database` subnets; never publicly accessible |
| Observability | Enhanced Monitoring, Performance Insights, alarms on replication lag, CPU and memory |

## Minimal usage

```hcl
service_name = "checkout"
environment  = "prod"
```

Then narrow network access to your workloads:

```hcl
primary_allowed_security_group_ids   = ["sg-0123..."]  # EKS pod/node SG, us-east-1
secondary_allowed_security_group_ids = ["sg-0456..."]  # EKS pod/node SG, us-west-2
alarm_actions = {
  primary   = ["arn:aws:sns:us-east-1:111122223333:platform-alerts"]
  secondary = ["arn:aws:sns:us-west-2:111122223333:platform-alerts"]
}
```

## After the first apply

1. Connect once as the master user (secret in `master_user_secret_arn`) and create the
   application role(s) listed in `iam_database_users`:
   ```sql
   CREATE ROLE app LOGIN;
   GRANT rds_iam TO app;
   GRANT ALL ON DATABASE checkout TO app;
   ```
2. Attach `db_connect_policy_arn` to the service's EKS pod role (IRSA / Pod Identity).
3. Applications generate an auth token (`rds generate-db-auth-token`) and connect over TLS.
4. Reboot the writer once after creation so `shared_preload_libraries` (pgaudit) takes effect.

## Regional failover

* **Planned switchover (no data loss):**
  `aws rds switchover-global-cluster --global-cluster-identifier <global_cluster_id> --target-db-cluster-identifier <secondary cluster ARN>`
* **Unplanned (primary region down):**
  `aws rds failover-global-cluster --global-cluster-identifier <global_cluster_id> --target-db-cluster-identifier <secondary cluster ARN> --allow-data-loss`

After either, point applications at the promoted cluster's writer endpoint
(`secondary.writer_endpoint`). IAM permissions already cover both clusters.
The module ignores the attributes AWS rewrites during a failover, so a
subsequent `tofu plan` will not try to undo it.
