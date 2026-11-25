# Aurora PostgreSQL for regional recovery

Deploy one root/state per service and environment. This creates one Aurora Global Database, not two independent writers. The second region continuously receives storage-level replication and has the same provisioned compute as the first. Each region has two DB instances in distinct AZs. Budget for all four instances, storage, replicated writes, cross-region traffic and backups.

## Before deployment

Copy `minimal.tfvars` and replace its example security groups, SNS topics and workload role name(s) with real ones in the deployment account. Use the SG actually attached to the workload pod or node ENIs, with outbound access to TCP 5432. Each region must have exactly one VPC named `apps-<environment>` and private `tier=database` subnets in at least two AZs. This module neither changes routes nor opens public access. The example assumes the active EKS service moves with the writer; the standby EKS environment can reach its local cluster without cross-region routing. Configure and test service traffic failover separately.

Both SNS topics must allow RDS event notifications and CloudWatch alarms and have monitored subscriptions. Confirm support for the selected Global Database engine minor and instance class in **both** regions. Load-test capacity against peak write traffic. Use a locked, encrypted, access-controlled remote state backend **before apply**: state and saved plans contain the generated administrator password, even though outputs do not. Restrict the replicated Secrets Manager secret and regional keys to database operators; do not grant workloads access to them. Keep the state and keys available for restore and audit.

```
tofu init
tofu plan -var-file=checkout.tfvars -out=checkout.plan
tofu apply checkout.plan
```

## Connect the service

From an authorized private maintenance client, use `admin_secret_arn` to bootstrap `app` on the writer. For each configured PostgreSQL username create a login, grant `rds_iam`, and grant only the schema/table/sequence permissions the service needs. For example: `CREATE ROLE checkout LOGIN; GRANT rds_iam TO checkout;`. Role creation and SQL grants replicate to the secondary. The inline IAM policy alone does not create a PostgreSQL user or authorize queries.

Use the AWS SDK with the EKS role to sign a fresh RDS authentication token for the **current writer region, actual regional cluster hostname, port 5432 and configured username** when opening connections. Pass it as the password, use the current RDS CA bundle and `sslmode=verify-full`. Pool connections and refresh tokens on reconnect. Configure each regional EKS deployment with its own `regional_endpoints[*].cluster`; the secondary is read-only until promoted. Do not hard-code IPs or sign tokens with a custom DNS alias.

## Regional outage runbook

1. Pre-authorize a recovery operator in the surviving region. Page on service write failures as well as replication lag; a lag alarm alone is not a regional health check. Inspect RDS events, writer health and the last reported `AuroraGlobalDBRPOLag` on the target. The 3,000 ms alarm is an early warning, **not a commit constraint**. Asynchronous replication normally targets seconds of loss, but a stale or missing sample cannot bound loss during a partition. If a strict maximum loss is contractual, this architecture alone cannot guarantee it.
2. Stop or fence traffic to the old writer. For an actual primary-region failure, the incident commander must accept potential loss of unreplicated transactions. From the surviving region run `aws rds failover-global-cluster --region <surviving-region> --global-cluster-identifier <global-id> --target-db-cluster-identifier <surviving-cluster-arn> --allow-data-loss`. Use managed **switchover** (`switchover-global-cluster`) instead for a healthy planned move with no data loss. Do not destroy/recreate clusters with OpenTofu to promote them.
3. Confirm the target is `IsWriter` in `describe-global-clusters` and available. Reconnect the surviving EKS deployment using fresh IAM tokens, verify a committed test write/read and shift service traffic. Reconcile uncertain checkout transactions using application idempotency keys, not blind replay. Regional promotion is operator-initiated; detection, authorization, connection retries and traffic cutover all count toward the minutes objective.
4. After recovery verify the former primary has safely rejoined as a secondary, or rebuild it using the RDS recovery procedure. Keep normal applies paused. `primary`/`secondary` in state denote **initial placement**, not current write authority. Restore lag monitoring on the current secondary and either switch back once synchronized or reconcile configuration and state with the new topology. Review a refresh and full plan for destructive actions before resuming applies; do not simply swap the provider regions.

Before production and regularly thereafter, drill both failover and switchback under representative load. Record the time to first successful application commit and compare committed transaction markers across the transition. Also test point-in-time restore: replication propagates operator mistakes as well as good writes. Both clusters use encrypted storage, 35-day backup retention, deletion protection and final snapshots. Schedule coordinated minor upgrades and break-glass password rotation; retain KMS keys for the full lifetime of backups and snapshots.
