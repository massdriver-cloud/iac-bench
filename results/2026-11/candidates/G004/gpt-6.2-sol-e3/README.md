# Aurora PostgreSQL for production services

This standalone OpenTofu root provisions one Aurora PostgreSQL 16 Global Database per service and environment. The initial writer is in `us-east-1`; `us-west-2` has an already-running, promotable cluster. Each region has two provisioned instances in different AZs. AWS can fail over between instances within a region; **regional failover is a separate, operator-authorized RDS action**, not a `tofu apply`. There is only one writer region at a time. The recovery cluster is not headless and does not need to create compute during an incident.

**Recovery objective:** use five minutes to restored application writes and three seconds of lost acknowledged writes as initial acceptance criteria. Aurora Global Database uses asynchronous storage replication. It is designed for low lag, but neither target is guaranteed: lag can exceed three seconds, and outage detection, promotion, connection recovery and service routing all count toward the RTO. The lag alarm reports the risk, not a bound on data loss. Do not treat this deployment as meeting an unconditional seconds-level RPO; if that is mandatory even with impaired replication, the write acknowledgment design needs to change.

## Deploy

1. Use OpenTofu 1.11 or later and AWS credentials in the environment for one AWS account. Use a separate, encrypted, access-controlled, locked remote state per service/environment for production; the root leaves backend configuration to the platform. The deployment role needs both regions' network read and provisioning permissions, including KMS grants and access to the bootstrap secret version. Keep provider debug logging off when handling credentials.
2. In each region, the account must have exactly one matching VPC tagged `Name=apps-prod` (or `apps-staging`) and private subnets tagged `tier=database` in at least two AZs supported by the selected engine and instance class. The network team must maintain private routing and NACLs; the module checks AZs and public-IP assignment, not route tables. Use a dedicated pod security group where possible; if using node SGs, any workload sharing them has network reachability. Permit workload egress to TCP 5432 and private DNS resolution. The module creates no VPC peering or public ingress.
3. Copy `minimal.tfvars` to a service-specific file. Replace the sandbox security group IDs and email address, set `service_name`, and supply the existing EKS workload role names in `app_iam_role_names`. Alternatively, attach the output `runtime_iam_policy_arn` in the EKS stack. Use pod identity or IRSA roles, not shared node roles. The policy permits only `rds-db:connect` as `app_runtime` against this database's two regional cluster resource IDs. Size `instance_class` for peak production traffic after promotion; the default `db.r7g.large` is a starting point, not a capacity guarantee.
4. Run `tofu init`, `tofu plan -var-file=service.tfvars`, and `tofu apply -var-file=service.tfvars`. Confirm **both** SNS emails and test receipt. Record the cluster ARNs, identifiers, regional endpoints and deployment identifiers in the service runbook outside the writer region. Make sure authorized incident operators can call RDS from the recovery region without relying on the failed region or state backend.

## Connect and bootstrap

- Connect from an approved private host or bootstrap job in the writer VPC. Retrieve `admin_secret_name` in the writer region using a separate privileged operator identity restricted to the secret and its KMS key. The password is generated ephemerally and passed through write-only inputs, not stored in OpenTofu plan/state. Secrets Manager holds a KMS-encrypted copy in both regions. Do not grant app roles access to it.
- On the writer, connect to `database_name` and create the runtime login once:

  ```sql
  CREATE ROLE app_runtime LOGIN;
  GRANT rds_iam TO app_runtime;
  GRANT CONNECT ON DATABASE <database_name> TO app_runtime;
  ```

  Replace `<database_name>` with the output. Grant `USAGE` on the service schema and only the needed table and sequence privileges. Use a separate owner/migration role, and do not grant app users schema ownership or admin privileges. These SQL changes replicate to the other region. The module intentionally does not run SQL migrations from the infrastructure runner.
- Require `sslmode=verify-full` with the AWS RDS CA bundle. For IAM login use the **regional cluster endpoint** for both the connection and the token hostname, and sign with the **same region** and username as the destination. Create a fresh token for new physical connections as needed (tokens last 15 minutes). Use bounded pooling, reconnection with backoff, and idempotent transaction retries. The output `global_writer_endpoint` tracks promotion in DNS but does not route EKS traffic or relocate IAM token signing; do not depend on it for IAM login. Do not connect to a reader endpoint for writes.

## Fail over and fail back

Before launch, keep the recovery service warm on EKS with the regional endpoint, working IAM login, enough capacity, and ingress routing ready. Run a synthetic transaction and an end-to-end alert from outside the initial writer region. CloudWatch alarms when the recovery cluster reports `AuroraGlobalDBRPOLag` at or above 3,000 ms, or has insufficient data; it also alarms on sustained CPU saturation in either region. Lag is sampled in one-minute periods and is not proof of write durability. Escalate missing telemetry, and do not use lag or CPU alarms alone to automatically trigger data-loss failover.

1. **Confirm incident and fence writes.** Incident command confirms loss of the writer region (not just a client or AZ failure). Stop sending writes to the old region, pause background consumers and migrations, and prevent traffic from reopening there. Check the target member and last observed RPO lag; record the potential data loss and obtain authorization per the incident procedure. In an outage the true last-commit loss may be unknown.
2. **Promote using RDS managed global failover.** Target the recovery cluster ARN; run this from the recovery region. `--allow-data-loss` explicitly accepts loss of unreplicated writes. Do not use it for a planned move.

   ```sh
   aws rds failover-global-cluster \
     --region "$RECOVERY_REGION" \
     --global-cluster-identifier "$GLOBAL_CLUSTER_ID" \
     --target-db-cluster-identifier "$RECOVERY_CLUSTER_ARN" \
     --allow-data-loss
   ```

3. **Verify then route.** Use `describe-global-clusters` from the recovery region to confirm the target member shows `IsWriter=true`; check that the cluster endpoint accepts a committed canary write using recovery EKS IAM and TLS. Drain stale pools, route client traffic and background writers to recovery EKS, then verify an end-to-end transaction. Reconcile uncertain checkout/payment operations using idempotency keys and authoritative payment-system records before replaying them.
4. **Restore redundancy.** Verify that RDS rejoins the former writer as a secondary and that replication is healthy; if it doesn't, coordinate repair with AWS before resuming normal changes. The provisioned lag alarm is pinned to the initial secondary and can alarm on missing data after promotion. Monitor `AuroraGlobalDBRPOLag` on the *actual* secondary while reversed, and clear the maintenance alert only once viable protection is restored. No `tofu apply` during the incident. Do not swap the provider region inputs to move the writer. Use RDS managed **switchover** back to the initial writer after the clusters are healthy and their engine versions support it; this synchronizes before the role change. Verify endpoints, drain and route again, and review a fresh plan before applying. If membership changed permanently, reconcile state and configuration before allowing delivery automation to resume.

Drill a planned switchover and rehearse unplanned promotion in staging under representative load. Measure time from first failed write to sustained successful writes, and compare acknowledged, timestamped canary commits recorded outside the original region with those present after promotion. Record lag, routing time and reconciliation results. Make these drills, deployment of externally monitored routing and tests of alert delivery launch gates.

## Data protection and maintenance

- Both regional clusters use customer-managed KMS encryption and enforce TLS. PostgreSQL connection logs are exported to encrypted CloudWatch groups with 90-day retention. Routine query text is not intentionally logged; treat all logs and performance telemetry as sensitive. Use parameterized SQL and avoid writing payment or customer data to error messages. Performance Insights is enabled with regional KMS encryption.
- Both clusters have 35-day automated backup retention and require final snapshots when deleted; cluster and global deletion protection are on. Replication is **not** protection against logical corruption or accidental deletes. Exercise regional point-in-time restore to a separate cluster, and use a separate backup account/immutable retention if required by policy. Retain keys for all retained backups and logs; the module blocks destruction of its KMS keys. Plan intentional decommissioning separately. These controls alone do not establish PCI compliance.
- Automatic minor upgrades are disabled. Use a supported Aurora minor in both regions, review current AWS security advisories and upgrade deadlines, test in staging, and change `engine_version` through the global cluster. Review maintenance windows and any pending-reboot parameters before rollout.
- The privileged password is not on automatic rotation. To rotate, use a maintenance change with the initial primary serving writes and replication healthy. Increase `admin_credential_version` once and apply; the new secret version is stored before RDS changes the password. There can be a brief mismatch, so do not use the admin login during that change. If apply fails, retry with the **same** generation. Verify login on the writer and the replica secret's status before closing the change. Do not rotate by replacing the secret version independently of the cluster.
