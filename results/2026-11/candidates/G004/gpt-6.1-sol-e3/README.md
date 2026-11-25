# Production Aurora PostgreSQL (standalone OpenTofu root)

Creates an **Aurora PostgreSQL Global Database**, not two independent databases and not a cross-region snapshot restore. Defaults: us-east-1 writer, us-west-2 hot standby; two provisioned db.r7g.large instances per region, in different AZs, equally sized for recovery. Aurora provides automatic in-region instance failover. Cross-region promotion is an explicit, managed operational action; see [RUNBOOK.md](RUNBOOK.md).

## Recovery contract — read before adopting

Design targets: **RTO <=5 minutes**, **RPO <=5 seconds**, subject to measured workload and a rehearsed, continuously staffed incident response. The hot secondary avoids provisioning or restoring during an outage. Global storage replication normally lags by less than a second.

**These are targets, not guaranteed bounds.** Aurora Global Database replication is asynchronous. An arbitrary region failure or prolonged replication interruption can lose more than five seconds. Neither a lag alarm nor a failover API call enforces a hard five-second RPO. PostgreSQL's `rds.global_db_rpo` write-blocking feature has a minimum of 20 seconds; setting that would not satisfy this brief, so this module does not pretend it does. CloudWatch samples also cannot prove an instantaneous loss bound. If the business means an unconditional maximum rather than a disaster-recovery SLO, do not sign off this design: require an architectural decision about cross-region synchronous commit/consensus, write availability and latency before launch. No Aurora infrastructure module alone can deliver that promise.

Cross-region failover is **not automatic**: automated promotion on a single missing metric risks avoidable data loss. Page from the surviving region and use managed failover with explicit incident authorization. A tested on-call response, healthy standby, application routing, and IAM/TLS reconnect behavior are part of the five-minute target, not optional follow-up work.

## Deploy

```sh
tofu init
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=service.tfvars
```

`minimal.tfvars` supplies literal example values for every required input and is the smallest supported topology (four DB instances). Replace the security groups, **existing** workload role names and mailbox with your service's values before apply. No application VPCs, EKS clusters, role trust policies or network transit are created. Both providers use the same environment-supplied AWS account credentials. Distinct commercial US regions are configurable; confirm engine/class/Global Database availability in both before changing defaults. Engine minor is pinned; upgrades are deliberate, coordinated operations, not automatic regional drift.

Required service inputs:

| Input | Meaning |
|---|---|
| `name` | Unique service name, e.g. checkout |
| `eks_security_group_ids` | `{ primary = [...], secondary = [...] }`, workload pod/node SGs in each local VPC |
| `application_role_names` | Existing IRSA/Pod Identity role **names**, for both EKS regions |
| `alarm_email` | Monitored on-call mailbox; confirm both regional SNS subscriptions |

Other defaults include environment `prod`, database `app`, IAM SQL user `app`, Aurora PostgreSQL `16.6`, two instances per region, and a 35-day PITR window. Environment can also be `staging`; the same safety defaults apply. See variable descriptions for overrides. Budget for four full instances, two regional storage copies, inter-region replication, KMS, logs and monitoring; this intentionally isn't a low-cost development topology.

### Network assumptions

The network team supplies exactly one VPC tagged `Name = apps-prod` (or `apps-staging`) **in each region** and subnets in it tagged `tier = database`. At least two distinct AZs with public IP assignment disabled are required. Subnet groups use only those subnets; instances explicitly disable public access. Verify private route tables, NACLs, VPC DNS and workload egress in the network review; a tag/public-IP flag alone is not proof of route-table isolation.

Database SGs allow only TCP 5432 from the supplied local EKS security groups and have no initiated egress rules. Security groups are stateful, so replies work; Aurora global replication uses AWS-managed infrastructure, not VPC peering. There is no internet ingress, CIDR-wide ingress, or database port exposed to all of a VPC.

This is an **active/passive write architecture**: application write traffic is served in the current writer's region. The other region can use local read-only endpoints before promotion and local writes afterward. Moving customer traffic to the surviving EKS region is the service team's routing responsibility. Simultaneous writes from remote-region EKS to a single writer require a separately reviewed routed inter-region network/access design; cross-region SG references are not a substitute, and this module does not silently open CIDRs or build a transit network.

## Authentication and SQL bootstrap

Both regional clusters enable IAM DB authentication. A narrowly scoped `rds-db:connect` policy names the **regional cluster resource IDs**, not the cluster names or global ID, and the requested SQL usernames in both regions. It is attached to every supplied workload role so regional promotion needs no IAM policy edits. The module does not change role trust, grant secret retrieval to applications, or grant database administrator privileges.

IAM authorization does not create PostgreSQL roles or grant SQL permissions. From a controlled, network-connected bootstrap job, retrieve the bootstrap secret with an explicitly authorized operations role (`secretsmanager:GetSecretValue` and KMS decrypt) and connect to the initial writer as `cluster_admin` with `sslmode=verify-full` and the current AWS RDS CA bundle. For the defaults, provision:

```sql
CREATE ROLE app LOGIN;
GRANT rds_iam TO app;
REVOKE ALL ON DATABASE app FROM PUBLIC;
GRANT CONNECT ON DATABASE app TO app;
-- Connect to database app before the following statements:
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO app;
-- Repeat these default privilege grants for your actual migration/object owner:
ALTER DEFAULT PRIVILEGES FOR ROLE cluster_admin IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO app;
ALTER DEFAULT PRIVILEGES FOR ROLE cluster_admin IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO app;
```

Use a separate controlled migration identity for DDL. Adapt the schema grants and usernames to the service; do not grant `rds_superuser`, object ownership, or `CREATE` to the runtime identity. SQL changes replicate to the standby. No shell provisioners, public bootstrap paths, or database provider connections are used during infrastructure apply.

Workloads generate short-lived IAM tokens with the AWS SDK/CLI from IRSA or Pod Identity credentials, for the **current regional writer's actual hostname and region**, port 5432 and exact SQL username. Use TLS `verify-full`; refresh credentials for new connections (tokens last 15 minutes), reuse bounded pools, and back off/reconnect after failover. Do not generate tokens for a custom CNAME. Regional endpoints and the AWS-managed global writer endpoint are outputs; see the runbook for reliable regional discovery and pool cutover. Applications need not receive RDS control-plane privileges: your deployment/failover controller can distribute the selected region and endpoint.

## Security, protection and operations

* Both storage copies, snapshots, Performance Insights and PostgreSQL logs use rotating regional customer-managed KMS keys. Independent keys avoid dependency on the failed region's KMS API. SNS topics are encrypted with separate notification keys and scoped publisher permissions.
* TLS is enforced in both cluster parameter groups; RDS CA is pinned to `rds-ca-rsa2048-g1`. Clients must validate certificates and maintain their CA bundle. TLS enforcement alone does not make clients validate server identity.
* A random 40-character bootstrap password is held in Secrets Manager and replicated, encrypted with the DR-region key. It is **not an application credential**. No password output is provided. It **exists in OpenTofu state and saved plans**. Configure a locked, encrypted, versioned remote backend with least-privilege access before real deployment; local state is not production-safe. The module intentionally does not invent an account-specific backend. Exclude state, plans and secret-bearing tfvars from source control.
* Bootstrap password rotation is a coordinated runbook task, not an enabled automatic rotation schedule. Update the database and replicated secret together, verify replication, and reconcile infrastructure state. Do not rotate just the secret or regenerate this random resource during an incident. If the primary Secrets Manager region is lost, the replica remains available; promote the replica to an independent secret before modifying it in that region.
* 35-day automated backups/PITR on the writer; retention is also configured on the standby for its promoted role. Do not assume secondary PITR history is identical. Final snapshots required on deletion; cluster/global deletion protection enabled. Keep customer-managed keys enabled and retained for as long as snapshots need decrypting. Global replication is not a backup: accidental deletion/corruption replicates too. Perform quarterly PITR restore-and-validate drills, and use the organization's independent immutable/cross-account backup policy if required by retention/compliance.
* PostgreSQL logs retained 90 days, enhanced OS monitoring every 60 seconds, Performance Insights for seven days, CPU/free-memory/local-storage alarms per instance and RPO-lag alarm from the DR region. Cluster event subscriptions cover all event categories. Alerts are operational metadata only; avoid putting payment data in SQL/logs. Tune thresholds and retention after load tests, without weakening recovery monitoring.
* Alerts are not a complete external availability probe. Add service-side synthetic read/write checks and routing health checks in both regions, managed outside this database root. Confirm SNS email subscriptions and production paging delivery before launch.
* During regional failover freeze infrastructure applies. Reconcile topology/state afterward; do not reverse provider regions or apply a plan that replaces a healthy promoted database. A deliberate decommission requires disabling deletion protection, reviewing snapshots and retention, and preserving KMS keys; routine `tofu destroy` must not be the production deletion workflow.

No remote modules are used. The checked-in provider lock file makes the validated provider selections reproducible. A successful plan validates configuration and discovery, not SQL bootstrap, IAM role existence, target SG ownership, engine availability, recovery objectives, or compliance certification; verify these in pre-production and drills.
