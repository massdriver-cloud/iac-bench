# Service database

One root/state per service and environment. This provisions an Aurora PostgreSQL Global Database, not two independent databases. Both regional clusters have two provisioned instances in different database-subnet AZs. The secondary is read-only until promoted; it does not need a restore or a scale-up to take writes.

**Before deployment:** replace the example identifiers in `minimal.tfvars` with the workload's IAM role name, regional pod/node security groups and subscribed, regional on-call SNS topics. Allow RDS events and CloudWatch alarms to publish to those topics. The role's trust policy must admit the correct service accounts in both EKS clusters. Each region must have exactly one `Name=apps-<environment>` VPC and private `tier=database` subnets in at least two AZs. Check engine release and instance-class availability in both regions, quotas, and load-test the class with production traffic. Budget for four instances, regional storage, backups, monitoring and cross-region replication. Coordinate minor-version upgrades in both regions.

Configure an encrypted, access-controlled, versioned remote state backend with locking before apply. State and saved plans are secrets: the generated administrator credential is in state as well as Secrets Manager. Restrict both the secret and its regional replica to platform administrators. Do not grant the application Secrets Manager access. Perform credential rotation as a coordinated database and secret change.

```
tofu init
tofu plan -var-file=minimal.tfvars -out=release.plan
tofu apply release.plan
```

**Enable application login once:** from an authorized private host, retrieve `admin_secret_arn`, connect to `app` on the writer as `platform_admin` with TLS hostname verification and the AWS RDS CA bundle. Run `CREATE ROLE app_runtime LOGIN; GRANT rds_iam TO app_runtime; GRANT CONNECT ON DATABASE app TO app_runtime;`. Grant only the schema, table and sequence privileges needed for this service, including default privileges for new objects under the migration owner. Do not make the runtime user the schema owner. These SQL grants replicate. Use EKS role credentials to generate a fresh regional RDS auth token for the exact regional endpoint, port 5432 and user `app_runtime` when opening a pooled connection. Use `sslmode=verify-full`. Test the recovery workload's login and read path before going live.

## Recovery contract and drill

Global replication is asynchronous. Seconds of data loss and recovery in minutes are design **targets**, not hard bounds: lag, detection, authorization, client reconnection and traffic switching all count. The recovery-region RPO alarm pages on a sampled maximum above 3,000 ms or missing data; it does not stop commits. A requirement never to acknowledge a write outside that bound needs an additional application write-admission/acknowledgment design. Keep a tested application deployment, identities, CA trust, connectivity, and an authorized responder in the recovery region. Monitor a synthetic transaction from the service independently of RDS events.

1. Pre-authorize the on-call responder to perform RDS managed global failover. Fence the old write path, stop jobs/retries that could duplicate payments, confirm the outage and record the last observed lag and transaction watermark. Pause IaC applies.
2. For a **drill or planned move**, use RDS *Switchover* and let replication catch up; do not use a data-loss failover. During a true regional outage use the RDS Global Database **Failover** action in the healthy region, select this global identifier and the healthy secondary as target, and explicitly authorize possible data loss. Do not create a replacement database with OpenTofu. Promotion across regions is not automatic.
3. Confirm the global membership reports the new writer and a read/write transaction succeeds. Route application traffic and workers to recovery EKS, use its regional endpoint and region for IAM tokens, and recycle connection pools. The global writer DNS output follows the writer, but does not create cross-region networking or reroute EKS traffic. Verify a checkout end to end, compare the transaction watermark and reconcile missing or ambiguous payments with the payment processor using idempotency keys.
4. Record time from first failed request to successful recovery and measured write loss. Re-establish a healthy secondary before calling DR restored. Review state and role-sensitive configuration (credentials, alarms, memberships) against actual topology before resuming applies; do not simply swap the region variables. Use a managed switchover after resynchronization for planned failback. Drill with realistic load at least quarterly, including a separate point-in-time restore test: replication also copies accidental deletes.

Deletion protection and final snapshots are intentional. Removing the service requires a reviewed backup/restore and teardown procedure, explicit disabling of deletion protection, and preserving the regional KMS keys as long as encrypted snapshots are needed.
