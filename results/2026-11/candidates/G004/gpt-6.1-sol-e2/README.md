# Production Aurora PostgreSQL Global Database

Standalone OpenTofu root module. No remote modules. Defaults: Aurora PostgreSQL 16.9, us-east-1 primary, us-west-2 hot secondary, `apps-prod`, four provisioned `db.r7g.large` instances. Both regions have two instances in distinct AZs. Both regions must have capacity to run the **entire** production workload; benchmark and increase `instance_class` before launch. This is intentionally not a low-cost development topology.

## Recovery contract — read before adopting

* Aurora Global Database provides storage-level asynchronous cross-region replication, normally sub-second, and managed regional failover typically takes minutes with a healthy, provisioned secondary. Local writer failures use Aurora's automatic in-region instance failover.
* **This is a minutes-RTO / seconds-RPO design target, not a hard guarantee.** A partition, replication backlog, large transaction, AWS control-plane failure, or slow operator/application recovery can exceed either target. Async Aurora cannot guarantee that at most a few seconds of acknowledged writes are lost in every regional failure. If the business means an unconditional limit, this architecture alone does not satisfy it; require an explicit risk decision or reconsider cross-region synchronous consistency and its latency/availability tradeoff.
* Regional promotion is **not automatic**. The included SSM Automation in the secondary region executes managed `FailoverGlobalCluster(AllowDataLoss=true)` and waits for the target to become the global writer. It is a deliberately privileged incident action, not an alarm action. Do not trigger it on a single missing metric. A trained 24x7 responder and rehearsed application traffic movement are prerequisites for minutes-level recovery.
* A 2,000 ms maximum replication-lag alarm pages from the secondary region (60-second metric periods). Missing data also alarms. This detects risk; it does not cap lost writes or provide second-by-second enforcement. The PostgreSQL `rds.global_db_rpo` write-blocking control has a 20-second minimum, so it is not presented as a way to enforce a few-second limit here.
* EKS regional traffic routing, application deployment, connection handling, and business transaction reconciliation are outside a database module. Run quarterly regional-failure drills and record **end-to-end** RTO and last durable transaction/RPO under peak write load, not merely how fast the RDS API returned.

## Inputs and network prerequisites

The account must already contain exactly one VPC tagged `Name = apps-prod` (or `apps-staging`) **in each region**. The module discovers only subnets in that VPC tagged `tier = database`. At least two AZs are required. Public IP assignment is rejected; the network team must also ensure these are actually private route tables (no direct IGW route), have sufficient free addresses, DNS enabled, and appropriate NACLs. The module does not create, alter, or peer VPCs.

Required inputs (all have literal examples in `minimal.tfvars`):

| Input | Meaning |
| --- | --- |
| `name` | Short service identifier, unique with environment in this account |
| `client_security_group_ids` | Existing EKS pod/node security groups, separately for each VPC |
| `database_users` | SQL usernames mapped to existing primary/secondary EKS IAM **role names**, not ARNs |
| `alarm_email` | A real, monitored on-call address |

Optional inputs: environment, two distinct US regions, engine version (16.x), instance class, extra tags. Use the actual two regions where your EKS clusters run. Confirm selected engine/class Global Database availability in **both** regions before changing defaults. The example SG IDs and role names are placeholders for your application's existing resources; replace them and the email before applying. `minimal.tfvars` is a plan example, not credentials or a production network inventory.

Each input application SG must belong to its respective VPC. Application SG egress must allow TCP/5432 to the new database SG. Database SGs permit ingress **only** from those groups, expose no public endpoint, and have no outbound rules (established response traffic is stateful; Aurora-managed replication does not require broad VPC egress). No application secret access, admin connectivity, cross-VPC connectivity, EKS trust relationships, or Kubernetes resources are silently granted. Pod Identity/IRSA roles and trust already belong to the service platform.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
# After replacing the example application values and reviewing cost/security:
tofu apply -var-file=minimal.tfvars
```

Configure an organization-owned, encrypted, access-controlled, locked remote state backend **before apply**; none is hardcoded because its bucket/key/account belong to your organization. Commit the provider lockfile, not state, credentials, plan artifacts, or real secrets. OpenTofu >= 1.9 and AWS provider 6.x are used.

## Security and first-use bootstrap

Storage, snapshots, Performance Insights, Secrets Manager, exported logs, and notifications are encrypted. Database keys are independent customer-managed regional KMS keys with annual rotation, so recovering the secondary does not depend on decrypting through the primary region. IAM login and TLS are enabled in **both** clusters. Backups are retained 35 days, logs 365 days, and deletion protection is enabled on both clusters and the global container. No broad application `rds:*` or administrator secret permissions are created.

An admin password is generated, not supplied or output, and placed in a customer-key-encrypted Secrets Manager secret replicated to the other region. The secondary inherits database credentials through physical replication. Applications must not use this account. Password material is still present in OpenTofu state: `sensitive` does **not** encrypt state. Restrict state, secret read, and KMS decrypt to deployment/break-glass roles. This module does not assume Aurora-managed password support for Global Database. Admin password rotation is an explicit coordinated operation: schedule it, rotate RDS and the secret together, verify both regional copies, then reconcile configuration/state through your approved secrets process; do not just rotate the secret or taint the password in production.

From an approved private administrative runner, use TLS `sslmode=verify-full` and the current AWS RDS CA bundle, retrieve the admin secret with a break-glass role, then bootstrap **on the current writer**, once:

```sql
-- Example for the checkout entry in database_users:
CREATE EXTENSION IF NOT EXISTS pgaudit;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CONNECT ON DATABASE app FROM PUBLIC;
CREATE ROLE checkout LOGIN;
GRANT rds_iam TO checkout;
GRANT CONNECT ON DATABASE app TO checkout;
CREATE SCHEMA checkout AUTHORIZATION dbadmin;
GRANT USAGE ON SCHEMA checkout TO checkout;
-- Grant only the tables/sequences and operations this service needs.
-- Example after migrations (runtime role intentionally cannot create objects):
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA checkout TO checkout;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA checkout TO checkout;
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA checkout
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO checkout;
ALTER DEFAULT PRIVILEGES FOR ROLE dbadmin IN SCHEMA checkout
  GRANT USAGE, SELECT ON SEQUENCES TO checkout;
```

Repeat role/schema grants for each configured SQL username. Adapt schema ownership/default privileges to your actual migration role; do not give runtime roles admin/DDL privileges. SQL is intentionally not executed by a provisioner: the OpenTofu runner need not reach the private database or place passwords on a command line. SQL role creation and `rds_iam` membership replicate globally; IAM policies and security groups do not, so this module creates those region-specific controls separately. IAM policies scope `rds-db:connect` to **cluster resource IDs** and the exact SQL username in both regions. IAM policy alone does not create PostgreSQL roles. Changes to `database_users` do not revoke existing SQL objects/grants automatically; offboard SQL roles explicitly.

Use the regional writer's real RDS cluster hostname for IAM login and token generation. Determine the writer from `DescribeGlobalClusters.GlobalClusterMembers[].IsWriter`, derive its region from the cluster ARN, and get its endpoint from `DescribeDBClusters` using a platform discovery component. Give that component read-only describe permissions as needed; application roles here only get `rds-db:connect`. A regional application can instead receive its local cluster endpoint via deployment configuration and start serving writes only after its local cluster has been promoted. Do not assume that the output labelled `primary` remains the writer after an incident.

```sh
# HOST is the currently promoted regional cluster endpoint, REGION its region.
TOKEN=$(aws rds generate-db-auth-token --hostname "$HOST" --port 5432 \
  --region "$REGION" --username checkout)
PGPASSWORD="$TOKEN" psql "host=$HOST port=5432 dbname=app user=checkout sslmode=verify-full sslrootcert=/etc/rds/global-bundle.pem"
```

Use SDK credential providers for IRSA/Pod Identity (no static AWS keys), fresh tokens for new connections (tokens expire after 15 minutes), connection pooling, bounded DNS caching, and reconnect/backoff. Test failover while pools hold existing connections. The global writer DNS endpoint is also output for clients that support it, but it is **not a substitute for regional IAM signing/discovery**. Do not generate IAM tokens against a custom Route53 CNAME. Reader endpoints may return stale data; do not use them for payment correctness checks.

Audit extensions and connection logging are preconfigured. Audit output can contain SQL literals and customer/payment data. Use bound parameters, restrict CloudWatch read access, prohibit logging payment credentials/PAN, and review statements and retention against your data-handling policy before onboarding a payment workload. This deployment is not, by itself, a PCI compliance certification.

## Operations and regional disaster recovery

Before go-live: confirm SNS email subscriptions in **both regions**; send a test alarm and an RDS event; integrate topics with the platform paging system if email does not meet the on-call response budget. Check lag while saturating writes, secondary capacity, IAM login, extension installation, backup restore, and application failover. Enable organization CloudTrail/AWS Config/security monitoring through the account baseline. Enhanced Monitoring and 7-day Performance Insights are enabled; dashboards can consume those and CloudWatch metrics. Version upgrades are explicit (no unattended minor upgrade), non-immediate, and maintenance windows are staggered. Track engine support/security patches and apply tested updates promptly; do not upgrade one global member independently.

### Unplanned primary-region loss

1. Incident commander verifies a regional event using independent application/RDS signals, records last known replication lag and durable business transaction ID, and authorizes possible data loss. Stop/fence old-region application writers/traffic where possible. Do not independently detach and promote both clusters.
2. From the **surviving secondary region**, run the provided automation. The caller needs `ssm:StartAutomationExecution` for this document and `iam:PassRole` for its output role (restricted to `ssm.amazonaws.com`), plus execution-status read permissions. Those powers are deliberately not attached to EKS roles.
   ```sh
   aws ssm start-automation-execution --region us-west-2 \
     --document-name checkout-apps-prod-promote-secondary
   # Use recovery_automation output for non-default names/regions.
   # Poll get-automation-execution until Success; inspect failure details otherwise.
   ```
   The automation uses the managed global failover API with explicit data-loss permission and waits up to 10 minutes for the secondary to be reported as writer. An API timeout is NOT proof that no promotion occurred: inspect global membership before retrying. If AWS control-plane failure prevents this action, escalate through the regional incident procedure/AWS support; do not blindly start independent promotions.
3. Confirm the target is writer and SQL `SELECT pg_is_in_recovery();` returns false. Test a write using the service IAM identity from the surviving EKS cluster. The global writer endpoint follows managed failover; IAM applications must reconnect using the new writer's regional endpoint and region. Shift EKS/customer traffic through the platform's existing regional traffic mechanism. Check service-level health and payment transaction reconciliation before declaring recovery. Record measured RTO and lost transaction range.
4. Quarantine old writers/connection pools until managed topology and AWS fencing are confirmed. Reconcile any lost/external payment transactions idempotently. Re-establish and verify cross-region redundancy as the failed region recovers. The fixed automation promotes the originally designated secondary only; it is not a general bidirectional failback controller.
5. Freeze OpenTofu changes during recovery. Refresh and review state/plan after the managed topology changes; never apply a plan proposing replacement or reparenting of a promoted production cluster. Resource labels describe physical regions, not permanent writer status. Use a planned managed global **switchover** for return to the original region once replication is caught up, then refresh/review again.

### Planned drills / failback

Use `aws rds switchover-global-cluster --global-cluster-identifier ... --target-db-cluster-identifier <target ARN>` from the target region for a healthy topology, rather than the lossy emergency automation. Verify synchronized data, application reconnection, IAM token region change, and alerts. Drill in staging first with synthetic transaction markers, then a controlled production exercise. The secondary-region lag alarm may stop publishing after role reversal; missing-data paging is intentional. Review/relocate the replication alarm for a prolonged reversed topology, and restore the intended topology before resuming routine configuration updates.

### Backup restore and retirement

Global replication is not a backup: accidental deletes and corruption replicate. Use point-in-time restore into a **new** isolated regional cluster from the 35-day backup window, validate data and IAM/network settings, and conduct a controlled cutover/rebuild of global membership. Restore-test regularly. Export/retain immutable long-term backups separately if your retention policy requires longer than 35 days.

Destruction is deliberately blocked by RDS deletion protection. Retirement requires an approved change to disable cluster/global protection, preserve/export required data, retain KMS decrypt capability and the admin secret, and resolve global membership before cluster deletion. Final snapshots are required and have deterministic `*-primary-final`/`*-secondary-final` identifiers: choose fresh identifiers before repeated retirements if those snapshots already exist. Logs are retained on destroy; Secrets Manager and KMS have 30-day recovery/deletion windows. Do not destroy database KMS keys while snapshots or replicated secrets still need them. Do not treat `tofu destroy` as a safe routine operation.
