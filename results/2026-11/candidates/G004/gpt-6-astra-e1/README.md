# Production Aurora PostgreSQL global database

Standalone OpenTofu root, with authored AWS resources and no remote modules. One deployment per service/environment/account. This is a **single-writer Aurora Global Database**, not two unrelated databases, a conventional cross-region read replica, or a snapshot-based recovery design.

## Recovery contract — read before production

The default topology is a writer cluster in `us-east-1` and a continuously replicated, fully provisioned secondary in `us-west-2`. Each has two `db.r7g.large` instances in different AZs. Either region has capacity to become the production writer without creating instances. Aurora handles instance/AZ failures locally; **regional failover requires an explicit managed global failover**.

AWS describes typical global replication lag below one second and regional database recovery in minutes. These are design targets, **not a guaranteed ceiling**. Asynchronous replication can lose all writes not yet replicated when a region is lost. The 3,000 ms RPO/replication alarms sample at 60-second intervals; they neither block commits nor prove a maximum loss bound. Aurora PostgreSQL's `rds.global_db_rpo` write-blocking control has a minimum positive setting of 20 seconds, so it cannot enforce a three-second contractual bound. It is deliberately not presented as doing so here.

**If “no more than a few seconds” is an unconditional business requirement, this Aurora design needs explicit risk acceptance or a different, synchronously cross-region replicated database/write protocol.** Backup retention does not solve that requirement. Actual end-to-end RTO also includes detection, authorization, AWS control-plane availability, connection recovery and application traffic routing. This module cannot guarantee those steps.

Recovery uses an operator-triggered SSM Automation in the surviving region, with a narrowly scoped service role and an explicit possible-data-loss acknowledgement. It does not automatically promote on a metric alarm: missing telemetry or a network partition alone is not proof that promotion is appropriate. A staffed, rehearsed on-call process is a production dependency, not an optional extra.

## What is built

- Encrypted Aurora PostgreSQL 16 global cluster, identical pinned minor versions, provisioned instances, automatic local failover candidates and explicit AZ placement. No Serverless v1, scale-to-zero, automatic major upgrades or independent minor-version drift.
- Existing VPC discovery using **`Name = apps-prod` / `apps-staging`**, and existing subnets using `tier = database`, scoped to each VPC. At least two distinct AZs, with public-IP assignment disabled. No new VPCs, public endpoints, broad CIDR ingress, NAT gateways or cross-region peering.
- Port 5432 ingress only from the supplied regional EKS workload security groups. Security groups have no outbound rules; established return traffic is stateful and Aurora's storage replication uses AWS-managed transport. Network owners must verify private routes/NACLs and EKS outbound access; subnet tags alone do not prove routing isolation.
- Independent regional rotating customer-managed KMS keys; encrypted storage, snapshots, Performance Insights and PostgreSQL CloudWatch logs. TLS required by PostgreSQL configuration. Clients must still verify the server certificate.
- IAM DB authentication in **both** regions and `rds-db:connect` grants scoped to the two **cluster resource IDs** and one application database username. Existing IRSA/Pod Identity role trust is not altered. No master credentials or secret-read rights are granted to applications.
- Forty-character generated break-glass administrator password in Secrets Manager, with a secondary-region replica under its local key. Secret deletion recovery is 30 days. Global-database compatibility is the reason for explicit password/secret management rather than assuming RDS-managed credential rotation works with this topology. No automatic master rotation is claimed.
- 35-day regional PITR retention, encrypted snapshots with copied tags, final snapshots on deliberate removal, RDS deletion protection on both clusters and global cluster, and OpenTofu destroy guards on clusters, keys and administrator secret. Replication also replicates bad writes: PITR/restore tests remain necessary.
- PostgreSQL connection/disconnection logs retained for 365 days, without general/slow/error-statement SQL text logging. This reduces payment-data leakage; it is not a complete SQL audit or a PCI certification. Performance Insights/query diagnostic access must be privileged because query text may be sensitive. Enhanced Monitoring at 60 seconds and seven days of Performance Insights are enabled.
- Independent encrypted SNS alert channels in both regions, instance CPU/memory/missing-metric alarms, and global RPO/storage-lag alarms in the initial secondary region. A regional alarm cannot reliably report its own regional control-plane outage. External application write probes and AWS Health monitoring must feed the same incident response process.

## Inputs and installation

Required inputs are all represented literally in `minimal.tfvars`: `name`, `database_name`, `application_db_user`, `application_iam_role_names`, the two regional client security-group sets, and `alert_email`. It uses the smallest supported topology: two instances per region. **The example role, group IDs and mailbox are illustrative**; replace them with the existing service identities and security groups before a real apply. Credentials come only from the environment.

Other defaults: `environment = "prod"`, `primary_region = "us-east-1"`, `secondary_region = "us-west-2"`, `engine_version = "16.9"`, `instance_class = "db.r7g.large"`, `instances_per_region = 2`. Staging receives the same safety controls. Versions and instance types must be available for Global Database in both chosen commercial US regions; check AWS regional support before changing them. Budget for four instances, two copies of storage/backups, cross-region replication, logs, monitoring, keys and secrets. Load-test capacity; a default class is not a checkout throughput guarantee.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
# Review and save your production plan using a service-specific tfvars file before apply.
```

Commit the provider lock file. Use an organization-managed **encrypted, versioned, access-controlled, locked remote state backend**, recoverable outside the primary region, before applying real data. The root deliberately does not hard-code a team's bucket/account or create its own backend. A bare local backend is suitable only for evaluation. Passwords exist in state and saved plans despite sensitive redaction. Do not commit either; protect state, plans, CI artifacts and backend keys as production credentials. Disaster recovery automation does not depend on OpenTofu or access to this state.

Deployment identity needs AWS permissions in both regions plus account-level IAM management and `iam:PassRole` for RDS monitoring and SSM recovery. It must be allowed to create the RDS service-linked role if the account does not have one. Existing network and application roles remain owned by their teams. The root does not configure EKS ingress, application regional routing, VPC endpoints or CA distribution.

## One-time database bootstrap and service integration

1. Confirm **both** SNS email subscriptions and test real delivery to staffed paging. If your paging system supports SNS directly, subscribe it to the two `alert_topic_arns`. An unconfirmed mailbox is not monitoring.
2. On a hardened migration runner inside the current writer VPC, retrieve the administrator secret using a tightly controlled break-glass/bootstrap IAM role. Grant that role only the necessary `secretsmanager:GetSecretValue` and regional `kms:Decrypt`. Neither an application role nor the recovery automation role has those rights.
3. Connect to `regional_endpoints.primary.writer` with `sslmode=verify-full`, the current AWS RDS CA bundle, user `dbadmin`, and the initial database. Keep the password out of command arguments/history/logs (use a short-lived mode-0600 pgpass file and remove it). Run:

   ```sh
   psql "host=$DB_HOST port=5432 dbname=$DB_NAME user=dbadmin sslmode=verify-full sslrootcert=$RDS_CA" \
     -v db_name="$DB_NAME" -v app_user="$APP_USER" -f bootstrap.sql
   ```

   `bootstrap.sql` is idempotent and grants runtime DML only in schema `app`, with no schema creation, superuser or role-management rights. This explicit post-apply step is necessary: setting the AWS IAM authentication flag does **not** create PostgreSQL roles or grant `rds_iam`. Bootstrap and schema changes replicate; never run them independently on the read-only secondary. Run schema migrations in a privileged controlled pipeline, not as the runtime role. The supplied default privileges cover objects created by `dbadmin`; a separate migration owner needs corresponding defaults.
4. Configure each region's EKS deployment with its **local regional cluster endpoint**, local AWS region, database and application username. Use its workload IAM credentials to generate a fresh RDS auth token for that exact endpoint/port/user/region, and connect with `sslmode=verify-full` and the RDS CA. For example:

   ```sh
   aws rds generate-db-auth-token --hostname "$DB_HOST" --port 5432 \
     --region "$AWS_REGION" --username "$APP_USER"
   ```

   Use an SDK/driver token callback in production, not a long-lived Kubernetes password Secret. Tokens expire after 15 minutes for new connections; existing sessions can continue. Pool connections, refresh tokens on reconnect, use bounded exponential backoff and avoid unbounded DNS caching. Do not substitute a custom CNAME when signing the token.
5. The exported AWS-managed global writer endpoint follows managed failover, but **the documented IAM integration uses actual regional RDS endpoints** and signs in the active region. The root does not assume global endpoint IAM support or create cross-region VPC routes. The standby EKS deployment is warm but must not receive write traffic until its local database is promoted. Route service traffic to the surviving EKS region after the write readiness check succeeds.
6. Verify TLS enforcement, IAM allow/deny behavior, absence of public access, secret replication, two distinct instance AZs per region, backup retention, logs and healthy lag metrics. Prove an application write/read probe in the writer and read visibility in the secondary before onboarding production traffic.

## Regional outage runbook (execute from the surviving region)

Keep the document name, region, cluster ARNs and regional endpoints in the on-call system; obtain them from `recovery_automation` and `regional_endpoints` after initial deployment. Do not depend on a failed region to retrieve these outputs or credentials.

1. Declare an incident. Check external write probes, AWS Health and both regional signals; distinguish an instance/AZ issue from a regional outage. Check the secondary is available and recent `AuroraGlobalDBRPOLag` / replication lag. Missing or stale metrics mean **unknown** RPO, not zero lag. Record the potential lost-write interval; no stale metric can certify the last acknowledged transaction is safe.
2. Incident commander approves potentially losing unreplicated writes. Quiesce/fence old-region application traffic wherever possible. Use AWS **managed global failover**, which coordinates writer role changes; never detach a cluster and promote it as a parallel writer.
3. Start the pre-created document in the initial secondary region:

   ```sh
   aws ssm start-automation-execution --region us-west-2 \
     --document-name checkout-prod-recover-database \
     --parameters 'ConfirmDataLoss=I_ACCEPT_POSSIBLE_DATA_LOSS'
   ```

   Substitute your output values. Pre-authorize incident operators for `ssm:StartAutomationExecution` on this document, execution inspection, and `iam:PassRole` **only** for the recovery role to SSM. Do not give applications these permissions. The role can fail over only this global database and describe RDS state; no secret access, delete, detach or generic cluster modification.
4. Monitor with `aws ssm get-automation-execution --region <recovery-region> --automation-execution-id <id>`. The document checks membership, requests `FailoverGlobalCluster` with `AllowDataLoss=true`, and polls for the target writer and availability. It waits up to eight minutes; timeout is an escalation, **not rollback**. Inspect the AWS operation before retrying. If the target is already writer it does not initiate another failover. No fallback attempts a dangerous detach/promote.
5. Flush failed connections. Use the target's local endpoint and a newly signed local-region IAM token. Verify `SELECT pg_is_in_recovery()` is false and perform an idempotent application write/read probe. Shift application traffic to the healthy EKS region, verify checkout and business metrics, and reconcile any lost payments using external transaction/idempotency records. Database recovery alone does not route application traffic.
6. Verify the old region has rejoined as secondary and replication has converged when it returns. If AWS cannot rejoin it, follow the AWS global-database recovery procedure under incident control. Do not improvise a second independent writer. Reestablish global-lag alarms in the **new** secondary region; existing secondary-only alarms will need their placement changed after role reversal.

The document intentionally promotes only the original recovery location. Planned failback is a **managed switchover**, not another data-loss failover. After both clusters are healthy, synchronized and version compatible, invoke `aws rds switchover-global-cluster --global-cluster-identifier <id> --target-db-cluster-identifier <original-primary-arn> --region <current-writer-region>` during a controlled window, verify endpoints/readiness and route applications back. Drill both directions quarterly, recording detection-to-write RTO and the last acknowledged transaction present after recovery. A five-minute operational objective requires sufficient alerting/approval/connection-recovery budget; the automation timeout is not an SLA.

## Ongoing operations

- Do not swap region variables, change names or run a blind apply to perform/reverse a failover. Deployment labels identify geography, not current writer role. Before resuming IaC after an incident, refresh and inspect the global membership, password metadata, replication settings and every proposed action. Replication-source direction is ignored because AWS manages it. Never approve replacement of a live cluster to silence drift. Reconcile configuration with current AWS state, or complete a planned switchover first.
- Plan upgrades as coordinated Global Database maintenance, test in staging, keep regional engine versions compatible and patch promptly. Automatic minor upgrades are disabled to prevent uncoordinated drift. Apply is deferred to maintenance for modifications; static parameter changes need scheduled reboots. Do not blindly bump both versions and assume simultaneous multi-region updates are safe. Use AWS-supported secondary-first/minor or managed-global major procedures as appropriate.
- Use scheduled credential rotation for the break-glass identity under change control. A reviewed `tofu apply -replace=random_password.administrator -var-file=<service.tfvars>` updates RDS and the replicated secret; verify the new credential on the current writer and replica propagation before closing the change. They are not an atomic update. Do not rotate during failover or assume an out-of-band secret edit changes RDS. Applications continue using IAM. Restrict access and audit secret retrieval with the organization's CloudTrail controls.
- Quarterly, restore a PITR/snapshot into an isolated VPC/security group, check integrity and record restore duration. Test secondary-region backup/secret access independently. Global replication is not protection against logical corruption. Organization-wide immutable backup vaults, security audit pipelines and retention/compliance policies can be layered on; they are not claimed by this root.
- Destruction is intentionally blocked. Approved decommission requires editing destroy guards, disabling RDS deletion protection in a separate controlled apply, confirming independently restorable backups, and then removing global membership/resources in AWS-supported order. Preserve keys for every retained snapshot and secret. Final snapshot names use a deployment suffix; if reusing a prior final-snapshot name during another decommission, explicitly choose a new one to avoid collisions. Do not delete keys while any retained backup needs them.
