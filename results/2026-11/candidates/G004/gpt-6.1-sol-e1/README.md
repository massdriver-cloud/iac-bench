# Production Aurora PostgreSQL Global Database

Standalone OpenTofu root; **no registry modules**. One deployment/state per service and environment. It uses environment AWS credentials in one account and two commercial US regions. Defaults: `us-east-1`, `us-west-2`, environment `prod`.

## Recovery contract — read before adopting

This is an active/passive **Aurora Global Database**, not two unrelated regional databases and not a backup/restore DR scheme. Its storage-level asynchronous replication normally has sub-second lag; a pre-provisioned secondary supports managed regional promotion, typically in minutes. Each region also has two equal-sized instances in different AZs for local failover.

**Aurora cannot unconditionally satisfy “lose no more than a few seconds of writes.”** Global Database replication is asynchronous. Lag can exceed its usual value during network/service faults. Aurora PostgreSQL's smallest supported `rds.global_db_rpo` setting is **20 seconds**; this module sets that guard in both regions. It can block primary commits when the recovery region falls behind, intentionally trading primary availability for bounded replication lag. This is not a hard 3-second loss guarantee, and alarm telemetry is not a durability acknowledgment. The secondary alarms when replication lag exceeds 3,000 ms, or the metric disappears.

AWS does **not** automatically promote a Global Database across regions. Regional recovery here is a **24x7 operator-authorized managed failover**, with a prepared CLI command, warm capacity, application writer discovery and an exercised runbook. It is not unattended DR. Target detection + decision + promotion + reconnect within five minutes, subject to AWS control-plane availability; measure it under realistic load. If unattended promotion or a strict maximum of only a few seconds is a non-negotiable acceptance criterion, **do not declare this implementation compliant**. Obtain a business-approved RPO/RTO exception or select a cross-region synchronous/consensus database architecture (and accept its latency/availability tradeoffs). Do not mistake typical replication performance for an SLA.

## Decisions and defaults

* One encrypted global database; one initially writable cluster and one read-only recovery cluster. Secondary creation waits for primary instances. Storage replication uses AWS infrastructure, not customer VPC peering; no public ingress is required.
* Two provisioned `db.r7g.large` instances per region, explicitly placed in the first two sorted supplied AZs. Equal capacity avoids a promotion-time resize. This is a production floor, not a service sizing recommendation. Test peak checkout load and failed-AZ capacity. Four instances, cross-region replication and monitoring incur ongoing costs, including staging.
* Exact Aurora PostgreSQL **16.6** version pin with PG16 parameter groups; caller can choose another tested 16.x minor supported for Global Database in both regions. No automatic minor or major upgrades. Verify current AWS support/security advisories before first rollout and maintain a patch cadence. A major upgrade requires a parameter-family migration and rehearsal, not just changing this string.
* Existing `apps-prod` / `apps-staging` VPCs only. Caller passes the network team's private subnets tagged `tier=database`, keyed by their actual AZ, and the EKS client SGs. Explicit IDs avoid ambiguous tag selection and adopting someone else's network. The module validates shape/AZ diversity but does **not** query or prove tags, ownership or route tables. Before apply, verify each subnet belongs to the supplied regional VPC, is actually private, has the database tier tag, and matches its AZ key. All supplied SGs must belong to that VPC. Use common environment network outputs/inventory rather than inventing IDs.
* Only TCP 5432 from explicitly approved local client SGs; no CIDR, public ingress or outbound rules. RDS instances are not public. EKS pod ENIs must actually carry an allowed SG (node SGs are not always pod SGs); client egress, network ACLs, DNS resolution and routing must permit connections. No EKS resources or inter-region application network are created.
* Regional rotating customer-managed KMS keys encrypt databases, snapshots, bootstrap credentials, PostgreSQL logs and Performance Insights. Credentials replicate using the recovery region's key. Keep both keys usable during recovery. Workload roles receive no admin-secret permissions.
* IAM database authentication enabled in both regions, TLS forced server-side. Clients must verify the AWS RDS CA and hostname (`sslmode=verify-full`); download and maintain the official RDS `global-bundle.pem`. An IAM token is not a replacement for SQL grants.
* Random 40-character bootstrap administrator password, in Secrets Manager with a regional replica; no password output or required password tfvar. This explicit bootstrap scheme works without relying on Global Database support for RDS-managed master secrets. Password and secret version **are in OpenTofu state**. Restrict admin secret/KMS access to a break-glass or migration role; its host field is the **initial** writer, not a routing source. Plan and execute a coordinated password/secret rotation procedure with verification; there is no automatic SQL credential rotation in this root. Never independently change the secret or replace `random_password.admin` as a rotation shortcut.
* 35-day encrypted automated backups/PITR in each regional configuration, separate daily backup and weekly maintenance windows (UTC), mandatory final snapshots, deletion protection and `prevent_destroy` on data, keys and instances. Replication also replicates accidental deletes: it is **not** a backup. Exercise PITR restores separately; a restore is not the minutes-level regional outage path. Cross-account immutable backups require the organization's backup policy and are not provisioned here.
* PostgreSQL connection/disconnection/lock logs retained for 365 days with customer KMS encryption; log groups survive stack removal. SQL statements, bind values and error statements are suppressed to reduce payment/customer-data disclosure. Performance Insights (7 days, KMS-encrypted) and 60-second enhanced monitoring are enabled. Restrict access to diagnostics: query text/errors can still contain sensitive values. This is a security baseline, **not a PCI certification** or full SQL audit solution. Account owners should centrally manage the shared `RDSOSMetrics` log group's retention and access.
* Regional CPU, free-memory and missing-uptime alarms, plus recovery-region replication lag alarms, notify encrypted regional SNS topics. Confirm both email subscriptions and integrate the mailbox with paging. CloudWatch in a failed region cannot be assumed functional: the platform must also operate an application write/read synthetic probe from the surviving region or external monitoring and page on that signal. Lag alone cannot distinguish a quiet database from an unavailable primary. No alarm automatically discards writes by promoting a secondary.

## Instantiate

`minimal.tfvars` supplies literal examples for **every required root variable**. IDs and the on-call address are deliberately illustrative: they plan without network lookups but must be replaced with real inventory before apply. No cloud resources are discovered or implicitly adopted based on a potentially non-unique VPC tag.

Required inputs: `name`, `application_db_user`, `alarm_email`, `primary_network`, `secondary_network`. Each network contains `vpc_id`, `database_subnets = { AZ = subnet_id, ... }` (at least two), and a nonempty `client_security_group_ids` set. Optional inputs and validation are documented in `variables.tf`.

```sh
tofu init
# Configure an encrypted, access-controlled, locked remote backend before apply.
tofu validate
tofu plan -var-file=minimal.tfvars
# After replacing examples, reviewing the plan and satisfying rollout gates:
tofu apply -var-file=production.tfvars
```

Use a separate encrypted, locked remote state per service/environment, with recoverable versions and tightly scoped deployment access; do not commit local state or saved plans. Configure the organization's backend at the root (no backend/bucket/account assumptions are hard-coded). Keep `.terraform.lock.hcl` under version control. Credentials come from the environment, not tfvars. Deployment needs RDS, KMS grant administration, EC2 security-group, IAM/pass-role, Secrets Manager, Logs, SNS and CloudWatch permissions in the applicable regions.

## EKS login and application readiness

1. Attach `application_iam_policy_json` to the **existing workload's** IRSA / EKS Pod Identity role in both regions. It allows `rds-db:connect` only for the given SQL username and the two **cluster resource IDs**, not broad `rds:*` or identifier-based ARNs. The module does not take ownership of application IAM trust policies.
2. Through a VPC-connected controlled admin job, use the secret to connect to the initial writer and run `bootstrap.sql` with `-v app_user=<application_db_user>` against `database_name`. The script grants `rds_iam`, limited app-schema DML and default privileges, not superuser or schema DDL. Run migrations through a separately authorized identity; configure default privileges for that owner too. SQL objects/roles replicate to the recovery region. Verify the application has no password fallback.
3. Use regional **cluster writer endpoints**, not instance or reader endpoints. `discover-writer.py` demonstrates read-only API writer discovery from the surviving region, without printing a token. Attach `writer_discovery_policy_json` if using it; install `boto3` in the application/tooling environment. It returns a host and its correct IAM token-signing region. Generate tokens with the same host/port/SQL username immediately before connection; IAM tokens last 15 minutes. Do not log them. The managed `global_writer_endpoint` output is also available for compatible clients, but DNS alone does not change an SDK's token-signing region.
4. On disconnect or read-only errors, close stale pools, rediscover the writer, regenerate a token in **its region**, and reconnect with bounded jittered backoff. Refresh DNS, verify TLS and `SHOW transaction_read_only`, and use idempotency keys to handle ambiguous commits safely. Never automatically retry a non-idempotent payment transaction as if it definitely failed. Avoid long DNS caches; pool and retry settings are part of the recovery budget.
5. Before accepting production traffic, verify TLS rejection for plaintext, IAM login in both regions, SQL least privilege, confirmed paging, live replication metrics, backup/PITR recovery, pending parameter application, capacity and an end-to-end regional failover drill. Measure last acknowledged write versus last recovered write. Do not accept the deployment solely because `tofu plan` succeeds.

## Regional outage runbook

Keep outputs and commands in the incident system in advance; recovery must not require reading state in the failed region. Incident credentials and tooling must also be available in the secondary. Aurora provides local AZ failover automatically; regional failover is different.

1. Independent synthetic probe/pages detect primary write failure. Establish a regional outage rather than a single application's bad deploy. Stop/fence writes and automated retries to the old writer where possible, check secondary health and latest replication/RPO lag, and authorize the possible loss of unreplicated transactions. A stale or missing metric is **not** evidence of zero loss.
2. From the recovery region, run the prepared `failover_command` output. For the example deployment:

   ```sh
   aws rds failover-global-cluster --region us-west-2 \
     --global-cluster-identifier checkout-prod-global \
     --target-db-cluster-identifier <secondary-cluster-ARN> --allow-data-loss
   ```

   Require a dedicated incident role scoped to this global cluster and the applicable regional clusters, granting `rds:FailoverGlobalCluster` plus read-only describe permissions (and dependent permissions AWS requires for your engine/API version). Do not give failover permissions to workloads. This is a deliberate data-loss operation; do not run competing promotions or detach clusters as the normal path. If AWS cannot perform managed failover, escalate to AWS support and the database incident lead; do not improvise split writers.
3. Poll `describe-global-clusters` from the surviving region until status is `available` and the target member is `IsWriter=true`; check the target cluster/instances are available. The prepared command targets the original secondary; for subsequent incidents, inspect actual roles and regenerate the target instead of blindly replaying it.
4. Move/enable EKS service traffic in that region using the platform's existing traffic-management runbook. Applications discover the regional writer, re-sign IAM tokens and reconnect. Verify a real write/read round trip, backlog recovery and payment idempotency/reconciliation before declaring recovery. Record elapsed time and lost acknowledged writes. Database provisioning alone does not fail over application ingress.
5. Freeze infrastructure applies during the incident. Preserve the failed region for reconciliation; do not reverse region variables or rerun apply to fail back. After AWS has rejoined/rebuilt the old primary as a secondary and replication is healthy, run `tofu plan -refresh-only` and then a normal reviewed plan. Resource labels denote original locations, not permanent writer roles. Review any role-dependent differences, especially credentials and engine drift; **never approve replacement of data resources** as drift repair.
6. Failback is a planned, zero-data-loss **switchover**, only after the old region is caught up and both sides are healthy:

   ```sh
   aws rds switchover-global-cluster --region <current-writer-region> \
     --global-cluster-identifier <global-id> \
     --target-db-cluster-identifier <original-primary-cluster-ARN>
   ```

   Reconnect/re-sign again, restore service routing deliberately, and revalidate replication protection. Practice this quarterly and after engine/client changes. Planned switchovers wait for replication; they are not the command for an unavailable source.

## Change control and retirement

Maintain both regions on the same exact tested engine patch version; consult Aurora Global Database's coordinated upgrade procedure rather than allowing independent regional patching. Parameter changes use `pending-reboot`, cluster changes use maintenance windows, and automatic minor upgrades are disabled. Check parameter apply status and schedule controlled reboots/maintenance after changes. The managed-RPO guard can intentionally cause write stalls when the recovery region is isolated: alert and investigate rather than silently disable it.

Renaming a service/environment, replacing its network/AZs or changing provider regions can force replacement; lifecycle guards intentionally block unsafe plans. Retirement requires an approved code change to remove lifecycle guards, disable RDS/global deletion protection, preserve/verify independent backups and credentials, and select collision-free final snapshot identifiers. Retain KMS keys for all retained snapshots/logs, not merely for the running cluster. This root does not automatically destroy production databases or their recovery keys.
