# Production Aurora PostgreSQL global database

Standalone OpenTofu root module. No external modules. Initial writer: `us-east-1`; warm disaster-recovery region: `us-west-2`. These are configurable US commercial regions, in the same AWS account. Each region has two equally sized provisioned instances in distinct AZs. This costs **four instances**, two storage copies, replication traffic, backups, monitoring, and KMS; the recovery region is not a low-capacity pilot light.

## Recovery contract — read before approving production

Aurora Global Database is the AWS-native choice for fast regional recovery: physical asynchronous replication normally has sub-second lag, and managed regional failover normally completes in minutes. Neither is a contractual upper bound.

**This module cannot guarantee “at most a few seconds of lost writes” for every regional outage.** The PostgreSQL `rds.global_db_rpo` guardrail is set to **20 seconds**, AWS's minimum positive setting, in both regions. It can stall writer commits when the secondary falls behind. It is not synchronous replication and is not a strict five-second guarantee. The replication alarm pages at **1,000 ms**, using one-minute metric periods; it cannot prevent loss, and the last observed sample can be stale. An abrupt failure can lose acknowledged writes not yet replicated. Availability is also affected by the RPO guardrail during a replication/network outage.

Adopt this design only with explicit business acceptance of those semantics. If a hard bound of, for example, five seconds is non-negotiable, Aurora Global Database alone does **not** satisfy the requirement. Revisit the database architecture and synchronous cross-region acknowledgement, or the recovery requirement, before production approval. Do not claim the lag alarm or failover script makes that guarantee.

Recovery is **operator-authorized**, not alarm-triggered. A false-positive autonomous, data-losing promotion is unsafe. The module installs a one-command Systems Manager Automation in the recovery region that invokes AWS managed global failover and observes promotion. A 24x7 incident response, pre-authorized loss decision, tested application traffic failover, and regional readiness are prerequisites to a minutes-level *service* RTO. Single-region/AZ instance failure uses Aurora's automatic in-region failover instead.

## Inputs and prerequisites

Required inputs: `name`, `environment`, and `clients`. `minimal.tfvars` supplies literal examples for each. **Replace its example security group IDs and IAM role names with real workload resources before applying.** They are not created here. This root assumes the applying principal has permission to create RDS, KMS, IAM, Secrets Manager, CloudWatch, SNS, SSM, and security-group resources and pass the monitoring/recovery roles. AWS credentials come from the environment.

* `environment` is `staging` or `prod`. The network lookup contract is exactly one VPC tagged **`Name = apps-<environment>` per region**, and its existing subnets tagged **`tier = database`**. An ambiguous or absent VPC fails the lookup. At least two distinct AZs and disabled subnet public-IP assignment are enforced.
* The network team must maintain **private subnet route tables**, DNS resolution, and regional EKS-to-database connectivity. This module doesn't modify routes, create VPCs, or infer privacy solely from tags. Instances explicitly have no public access. No internet CIDR ingress is created; only TCP 5432 from the supplied regional security groups. Security groups have no initiated outbound rules (return traffic is stateful). Global replication is AWS-managed and needs no inter-region VPC peering.
* `clients` holds existing regional workload security groups and **IAM role names, not ARNs**. Prefer per-workload pod security groups; node-group security groups widen network access. Workload roles use existing EKS Pod Identity/IRSA trust. The module attaches only `rds-db:connect` for the named application database user to both regional cluster resource IDs; it does not alter workload trust or grant administrator/secret access.
* PostgreSQL 16.6, `db.r7g.large`, database `app`, and login `app_runtime` are defaults. Confirm the selected Aurora minor version/class is available and supports Global Database in both regions before apply. Pin a currently supported patch release according to your patch policy. Load-test both regions; larger services must increase `instance_class`.
* Set `alarm_email` and confirm **both** SNS subscriptions, or attach the two output SNS topics to your pager using your alerting stack. Topics without subscribers do not deliver pages. Production is not ready until an end-to-end test page reaches on-call independently of the primary region.

```sh
tofu init
tofu fmt -check
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=service-prod.tfvars
```

Use a separately bootstrapped, access-controlled, **encrypted remote state backend with locking, versioning, and recovery access independent of the primary region**. Configure it using your organization's backend configuration; no backend is hard-coded because the bucket, key and ownership are platform-specific. Local state is only for development. The generated admin password is sensitive but **is present in state and saved plans**. Never commit state, plans, real tfvars containing secrets, or crash logs. Enable OpenTofu state/plan encryption under your platform policy as additional defense. No password is output.

## Security and database bootstrap

Both cluster storage copies, snapshots, Secrets Manager credentials, and Performance Insights use customer-managed regional rotating KMS keys. Keys have a 30-day deletion window and deletion safeguards. A high-entropy 40-character admin password is generated; its secret is replicated to the recovery region under that region's key. Applications do not use it. A restricted platform bootstrap/break-glass role needs explicitly scoped secret read and KMS decrypt access; no such access is attached to application roles. Cross-region secret replication is asynchronous; rehearse retrieving the local replica. Rotate this infrequently used admin credential under a controlled procedure that updates the database and secret consistently (e.g. an approved replacement of the random password/version under change control). Automatic master-password rotation is **not** configured; do not rotate the secret alone. After promotion, reconcile which cluster is writer before changing credentials in IaC.

TLS is required server-side. Clients must use `sslmode=verify-full`, the AWS RDS CA bundle, and the actual native regional cluster endpoint. Do not use a vanity CNAME for IAM token generation or certificate verification. Use the target region when generating a 15-minute IAM token. Pool connections and refresh tokens on each new connection; tokens aren't static passwords. IAM authentication does not create PostgreSQL users or SQL permissions.

Run bootstrap once from an authorized private-network workstation/job against the initial writer, using the secret. SQL changes replicate to the recovery cluster. Example below uses default input names; substitute validated identifiers if customized:

```sql
-- Execute as platform_admin in database app. Never give the runtime user ownership.
CREATE ROLE app_owner NOLOGIN;
CREATE ROLE app_runtime LOGIN;
GRANT rds_iam TO app_runtime;
REVOKE ALL ON DATABASE app FROM PUBLIC;
GRANT CONNECT ON DATABASE app TO app_runtime;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
CREATE SCHEMA service AUTHORIZATION app_owner;
GRANT USAGE ON SCHEMA service TO app_runtime;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA service TO app_runtime;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA service TO app_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA service
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app_runtime;
ALTER DEFAULT PRIVILEGES FOR ROLE app_owner IN SCHEMA service
  GRANT USAGE, SELECT ON SEQUENCES TO app_runtime;
ALTER ROLE app_runtime IN DATABASE app SET search_path = service, pg_catalog;
```

Use a separate controlled migration identity that `SET ROLE app_owner` before creating objects. Do not grant that identity or ownership to runtime roles. Adapt table grants if the service needs less access. Login to both regions using the actual EKS roles during acceptance testing; secondary writes should fail before promotion. Test IAM permissions independently from SQL permissions.

```sh
export PGHOST='<active-region native cluster endpoint>'
export PGPORT=5432 PGDATABASE=app PGUSER=app_runtime
export PGSSLMODE=verify-full PGSSLROOTCERT=/path/to/global-bundle.pem
export PGPASSWORD="$(aws rds generate-db-auth-token --hostname "$PGHOST" --port 5432 --region us-east-1 --username "$PGUSER")"
psql -c 'select current_user, pg_is_in_recovery();'
unset PGPASSWORD
```

Connection/disconnection logs go to pre-created CloudWatch log groups retained for 365 days; CloudWatch encrypts logs at rest with its service-managed encryption. Statement and slow-query logging are disabled to reduce payment/PII exposure. Error logs can still include sensitive context: prohibit logging card data, restrict log/Performance Insights access, and review redaction and SQL logging requirements. Never store prohibited payment authentication data. This is infrastructure hardening, **not PCI compliance certification**. CloudTrail, organization audit retention, vulnerability/patch management, data classification, and payment tokenization remain required platform controls. SNS notifications contain operational metadata, not database records or credentials.

## Regional outage runbook

Prepare all of this **before** an outage:

* Keep EKS, secrets/config, dependencies and sufficient capacity live in the secondary region. Configure each regional deployment with its **local regional cluster endpoint**. Only the current writer region serves write traffic. No cross-region application networking or global application DNS is created by this database root.
* Preconfigure and test the service's traffic manager to move traffic to secondary EKS. It must have a write-readiness probe, not merely a TCP probe. Native regional endpoints avoid needing to change database DNS during recovery and work with IAM/TLS. A regional cluster endpoint does not become writable until promotion.
* Authorize incident responders to call `ssm:StartAutomationExecution` on the output recovery document, inspect executions, and `iam:PassRole` **only** the output recovery role to SSM. Do not grant these to workload roles. Have credentials and a pager available without primary-region dependencies.
* Record a service RTO objective (e.g. five minutes), timestamped write canaries, and decision authority. Drill the whole path and measure actual RTO and lost acknowledged writes; provisioning success is not proof of recovery readiness.

During an initial-primary regional outage:

1. Declare the incident and verify failure from independent signals; review the latest replication lag and its timestamp. Stop/fence the primary-region application write path and prevent automated traffic failback. Accept that an unreachable writer cannot prove zero loss. The incident commander explicitly authorizes potentially lost writes. A single high-lag alarm is **not** permission to promote.
2. Run the installed Automation in the **secondary region** (document name and region are outputs):

   ```sh
   aws ssm start-automation-execution --region us-west-2 \
     --document-name checkout-prod-promote-recovery-region \
     --parameters 'Acknowledgement=FENCED_AND_ACCEPT_DATA_LOSS'
   ```

   This calls `FailoverGlobalCluster` with `AllowDataLoss=true` for the specific secondary ARN. It waits for global status `available` and the target member to be writer. AWS manages demotion/topology; do not detach/promote individual clusters as an ad hoc shortcut. Inspect SSM execution status and RDS events. A timeout does **not** cancel the AWS operation; inspect current state before retrying. The automation has a ten-minute safety timeout, not a ten-minute or shorter RTO guarantee.
3. On secondary EKS, authenticate with its regional IAM token and endpoint, confirm `pg_is_in_recovery() = false`, perform a committed write/read health check, and inspect the durable write canary to quantify loss. Promote service traffic to that region and reset/retry stale connection pools with bounded backoff. The module deliberately does not operate your EKS deployments or traffic manager.
4. Do not reenable the old write path. Inspect AWS's managed reattachment of the old region when it returns; repair/rebuild it as needed. Confirm only one global writer and healthy replication. Reconcile potentially lost payment operations with idempotency keys and the payment system of record.
5. Freeze regular IaC deployment during the incident. Afterwards refresh/inspect state and plans; names `primary` and `secondary` refer to **initial geography**, not current roles. Do not swap input regions or blindly apply a plan that replaces resources. Update lag alarms to follow the new secondary, and review backup/credential operations. This supplied recovery Automation intentionally targets only the initial recovery region; update the operational runbook before another incident in the opposite direction.

For a **planned** regional move or failback, use AWS managed `switchover-global-cluster` with the intended target ARN once replication is healthy; it synchronizes data for a no-loss planned transition. Do not use the emergency loss-accepting automation for routine maintenance. Drain connections, move service traffic, and repeat the same write-readiness checks. Schedule at least quarterly regional drills and after major application/engine changes. Budget detection, authorization, promotion, traffic routing, and reconnection separately; minimize authorization delay with a standing, tested incident policy.

## Backups, monitoring, upgrades and lifecycle

* Both regional cluster configurations set 35-day automated backup retention, distinct backup windows, final snapshots, and copied snapshot tags. Verify actual secondary-region PITR support/restore behavior for the chosen engine version; don't infer it from a configured number. Replication propagates accidental deletes and logical corruption, so it is **not a backup**. Test PITR and final-snapshot restores into isolated networks monthly. Consider organization-managed cross-account immutable AWS Backup copies for ransomware/longer retention; not created here.
* CPU >80% and free memory <1 GiB for three minutes alarm on every instance. Replication lag >1 second alarms in the initial secondary; missing metric data breaches intentionally. Cluster events go to regional SNS topics. Enhanced Monitoring runs every 60 seconds, Performance Insights retains seven days, and PostgreSQL logs retain one year. Subscribe/test paging before go-live. Retune capacity thresholds based on load tests and add service-specific connection, transaction latency, lock and error-rate SLOs.
* Maintenance is scheduled on Sunday UTC and staggered across instances; backup windows don't overlap maintenance. `apply_immediately=false`, no implicit minor-version upgrades, and no major-version upgrades. The platform owns a patch cadence: test then explicitly coordinate compatible engine upgrades across the global topology, following AWS's global-database upgrade ordering. Parameter changes are pending-reboot; schedule/verify activation. No surprise forced reboots are requested by this module.
* Global/cluster deletion protection, `prevent_destroy` on clusters/instances/keys/secret, 30-day secret recovery, and final snapshots protect against ordinary mistakes. These also deliberately block replacements and `tofu destroy`. A reviewed retirement change must explicitly remove lifecycle protections and disable AWS deletion protection, verify independent backup restores, then delete secondary/global membership in the appropriate AWS order. Preserve keys and final snapshots for the retention period. Removing configuration or state bypasses some IaC protections; restrict those operations and KMS scheduling permissions.

The clean plan establishes configuration/schema validity against the supplied environment, not an applied database, working IAM SQL login, supported production capacity, or a measured recovery guarantee. Complete the acceptance gates above before serving customer traffic.
