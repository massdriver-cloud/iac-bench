# Production Aurora PostgreSQL — standalone OpenTofu root

This root creates an **Aurora PostgreSQL Global Database**, not a cross-region backup/restore solution. It has a provisioned writer and failover reader in the initial primary region, and two equally sized, already-running instances in the secondary region. Each pair spans two AZs. Default placement is `us-east-1` / `us-west-2`; default capacity is four `db.r7g.large` instances total. Storage replication uses the Aurora global storage layer. Regional promotion does not require restoring backups or provisioning compute.

## Recovery contract — read before production approval

The design targets **recovery within minutes and typical write loss of seconds**. Aurora global replication is asynchronous (normally sub-second). This is **not a contractual maximum of a few seconds of data loss**, and neither an infrastructure plan nor AWS's typical replication latency proves that requirement. Aurora PostgreSQL's built-in `rds.global_db_rpo` guardrail has a **20-second minimum**. This module enables that minimum on both members; the primary can block commits if its secondary falls too far behind. That trades write availability during a replication/secondary failure for a tighter loss bound, but does not turn replication into synchronous cross-region commits.

Two-second replication/RPO lag alarms warn of target violations. Their 60-second sampling is monitoring, not a per-transaction guarantee. A missing lag metric on a writer is expected, so lag alarms ignore missing data; instance telemetry alarms separately report missing data. Add independent end-to-end probes from the surviving region and external paging to detect a whole-region failure, including CloudWatch failure.

**If “no more than a few seconds” is an absolute bound in every failure, this asynchronous Aurora design cannot honestly certify it. Obtain explicit business acceptance of this limitation, or change the data/write architecture before deployment.** Warm regional capacity, an authorized 24x7 responder, reachable recovery APIs, and rehearsed application traffic movement are all necessary for a minutes-level RTO. Cross-region failover is NOT automatic; automatic AZ-level failover is provided by Aurora.

## Inputs and deployment

Required service inputs:

* `name`: unique database/service identifier within the account.
* `primary_client_security_group_ids`, `secondary_client_security_group_ids`: existing, local EKS pod/node security groups in each selected VPC. No CIDR-wide access and no public endpoints are created.
* `application_role_names`: existing IRSA or EKS Pod Identity role names. Their workload trust is owned by the EKS platform. This module attaches only a two-region, exact-user `rds-db:connect` policy, never admin-secret access.
* `alarm_email`: on-call/paging mailbox; confirm BOTH SNS subscriptions after applying.

Optional inputs and their defaults are documented in `variables.tf`. VPC discovery assumes exactly one VPC tagged **`Name=apps-prod`** (or `apps-staging`) in each region. Only subnets in that VPC tagged **`tier=database`** are selected. They must span at least two AZs and disable public IP assignment. The network team must guarantee private route tables, DNS, NACLs, and client egress to port 5432. The module does not modify the shared network or create VPC peering. Normal traffic is served by the primary-region EKS service; DR moves service traffic to EKS in the promoted region. Cross-region SQL traffic, if desired, needs separately approved routing and ingress rules.

`minimal.tfvars` supplies literal examples for every required variable and is the smallest supported topology. Replace the example security-group IDs, IAM role name and mailbox with real service inputs before apply. Existing shared VPCs/subnets and client identities are prerequisites, not created by this root.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=service-prod.tfvars
```

Pin/check engine availability and instance orderability in BOTH regions before applying or upgrading. Engine 16.6 is the pinned starting version, with the PostgreSQL 16 parameter family. Automatic minor upgrades are disabled to avoid uncoordinated global version drift. Keep the generated provider lockfile in source control. Routine changes use maintenance windows, not `apply_immediately`.

### State and credentials

Configure a secured remote backend **before applying**: encrypted, versioned, access-controlled state with locking and recovery access outside the primary region. This root intentionally does not assume a particular organization's state bucket. Local state is not suitable for production.

The generated 40-character bootstrap password is stored in an encrypted Secrets Manager secret with an encrypted replica in the other region. It is **also present in OpenTofu state**. Sensitive handling/redaction does not encrypt state. Restrict state, plan artifacts, secret reads and KMS decrypt to deployment and break-glass operators. Do not grant these to application roles.

Applications never use the master password. A dedicated operator must implement and test administrative-password rotation with synchronized RDS/secret/state updates; this module does not claim automatic password rotation. Use a tightly controlled, audited break-glass process and test that the regional secret replica and KMS permissions work without the primary region. Never read the primary-region secret as a dependency of normal DR application login.

## First-use IAM login bootstrap

Run from an authorized private-network admin session using the bootstrap secret. SQL is deliberately not run by a local-exec provisioner: the provisioning runner need not have database network access. With the default database/user, run the following once on the global writer (adjust names to your variables):

```sql
CREATE ROLE app_iam LOGIN;
GRANT rds_iam TO app_iam;
GRANT CONNECT ON DATABASE app TO app_iam;
-- Reconnect to app as the bootstrap administrator:
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app_iam;
-- A separate migration owner creates service objects. Grant only the required
-- SELECT/INSERT/UPDATE/DELETE and sequence privileges on its objects, and set
-- ALTER DEFAULT PRIVILEGES FOR ROLE <migration_owner> accordingly.
```

Do not make the application a superuser or grant it schema creation by default. Apply migrations/privileges and test before opening service traffic. Roles and grants replicate to the secondary. IAM policy alone does not create a PostgreSQL login.

Use the **active regional cluster writer endpoint** as host, port 5432, `application_database_user`, AWS RDS CA bundle and `sslmode=verify-full`. Generate the IAM token with the active writer's region and exact AWS hostname. Tokens last 15 minutes; use refresh-aware pooling (not a password cached forever). TLS is required by `rds.force_ssl=1`. On failover change BOTH endpoint and token-signing region, discard stale connections, and retry with bounded backoff and idempotency keys.

A global writer endpoint is output for clients compatible with it, but the IAM client contract here deliberately uses regional AWS endpoints. Do not assume arbitrary DNS aliases or the global name work with IAM signing/certificate verification. The `primary`/`secondary` output keys describe initial placement, not live write ownership after promotion.

## Regional outage runbook

Assign a 24x7 incident role before go-live. Grant it `ssm:StartAutomationExecution` and read execution status for the exact recovery document in the SECONDARY region, plus `iam:PassRole` on the output recovery role, conditioned on `iam:PassedToService=ssm.amazonaws.com`. Do not grant these to EKS application roles. The automation role can only fail over this global database and describe RDS metadata; it cannot read passwords or run SQL.

1. Declare the incident from outside the failed region. Pause infrastructure pipelines. Verify the target region and secondary instances are healthy; inspect the last reliable replication/RPO lag and timestamps. A missing/stale metric does not prove zero data loss. Fence application traffic and writes in the former primary, including background workers, to avoid stale clients and duplicate side effects. Obtain incident commander approval for potential write loss.
2. Start the pre-provisioned SSM Automation in the **secondary region**. The runbook calls AWS managed `FailoverGlobalCluster` with `AllowDataLoss=true` and the exact secondary ARN, then waits for that member to become writer and available. It returns its regional writer endpoint. Example for the supplied defaults:

   ```sh
   aws ssm start-automation-execution --region us-west-2 \
     --document-name checkout-prod-promote-secondary \
     --parameters '{"DataLossApproval":["I-approve-potential-data-loss"]}'
   ```

   Monitor execution status. Timeouts abort rather than detach/recreate a cluster or bypass fencing. The 15-minute wait limits are safety timeouts, NOT a promised RTO. The document targets the original secondary only; it is not a toggle and must not be blindly retried after a successful promotion. If APIs fail, escalate to the tested AWS managed failover procedure/support; do not attempt backup restore as the normal minutes-level path.
3. Switch EKS application configuration in the surviving region to the returned endpoint and its signing region. Drain/recycle pools. Verify `SELECT pg_is_in_recovery()` returns false, perform a real IAM-authenticated write/read canary, then shift service traffic and resume workers. The module does NOT own your EKS deployments or DNS traffic manager; wire this step into your service's deployment/recovery automation **before launch**.
4. Record measured outage-to-first-successful-write RTO and sequence/timestamp-based lost-write RPO. Reconcile potentially lost checkout/payment writes against authoritative payment-provider events using idempotency keys. Do not assume acknowledgements from the former writer all survived.
5. Verify the old region rejoins as a secondary and replication becomes healthy. Inspect `DescribeGlobalClusters` membership; do not infer writer status from identifiers. Run a refresh-only plan and reconcile OpenTofu state/configuration with actual membership. **Do not blindly apply an old pre-failover plan** or accept replacement/promotion actions. Review source-region and primary-only credential attributes before permitting normal pipeline runs again. Labels remain placement labels.

### Planned switchover and failback

When both regions are healthy and synchronized, use `aws rds switchover-global-cluster --region <target-region> --global-cluster-identifier <name> --target-db-cluster-identifier <target-arn>` for a managed, synchronized switchover, not the data-loss-allowing emergency document. Verify supported matching versions first, pause/retry application writes, switch IAM client endpoint/region, and verify reads/writes. Fail back only after investigation, restored redundancy and business approval. Reconcile the state afterwards. Never use `tofu destroy`/recreate as failover.

## Security, backups and operations

* Per-region customer-managed KMS keys with annual automatic rotation protect storage, backups, Performance Insights and PostgreSQL log groups. Secrets are separately encrypted under those regional keys. Applications receive no decrypt or secret-read permissions.
* Both regional clusters have 35-day automated backup/PITR retention configured; final snapshots and snapshot tag copying are enabled. Test PITR restore and IAM/SQL bootstrap in an isolated VPC every quarter. Global replication is **not** protection against replicated logical corruption, and regional failover is not a substitute for restore testing. After promotion verify backups/PITR remain healthy on the active writer. For immutable compliance retention, add an independently administered backup-vault policy; this root does not claim backup immutability.
* Cluster/global deletion protection and OpenTofu `prevent_destroy` block accidental removal. Retirement requires an explicit code review, protection removal in a separate change, a verified retained snapshot and agreed retention of encryption keys. Final snapshot names must be unique if redeploying a retired service. Never delete KMS keys while retained snapshots/logs/secrets still need them.
* PostgreSQL connection/disconnection logs are exported for 90 days. General statement and duration logging are disabled to reduce sensitive SQL exposure. Error logs can still contain SQL/customer information; restrict log access and ensure apps parameterize queries and avoid sensitive literals. This is not complete SQL auditing or a claim of PCI compliance. Agree required audit scope/redaction/retention with security before handling payment data.
* Enhanced monitoring runs every 60 seconds; encrypted Performance Insights retains seven days. CPU, free memory, local storage and global replication/RPO lag alarms exist in both regions. Cluster failure/failover/maintenance notifications go to local SNS topics. Confirm delivery and integrate with actual paging; email alone is not an RTO assurance. Review capacity/connection limits under peak load, and increase both regional instance sizes together.
* Quarterly drills must include primary-region isolation, lagged secondary, unavailable primary IAM/secret endpoints, IAM token renewal after promotion, DNS caching/pool recovery, duplicate payment handling, PITR, failback, and safe post-failover OpenTofu reconciliation. Record RTO/RPO against the business acceptance criteria; block launch if these tests fail.

No remote modules, embedded cloud credentials, public database endpoints, application master-password outputs, or automatic destructive failovers are used.
