# Production Aurora PostgreSQL global database

This root module creates one Aurora PostgreSQL **Aurora Global Database** spanning two US regions. It is deliberately a complete root module: configure AWS credentials in the environment and run `tofu apply` with a tfvars file.

## Recovery design

- The primary cluster has at least two instances across private database subnets. The secondary has the same instance class and, by default, two instances as well. The primary writer and an in-region reader cover AZ failures without involving the other region.
- Aurora-managed physical replication keeps the secondary region current, normally with sub-second lag. The `AuroraGlobalDBRPOLag` alarm pages before lag grows beyond the configured five-second objective.
- Applications write through the **global writer endpoint**, not a region-specific writer endpoint. Aurora changes that endpoint when a managed switchover/failover promotes another region. Keep the application reconnect/backoff policy short enough to observe the DNS change.
- A managed unplanned cross-region failover normally restores write service in about a minute once initiated. Actual RPO is the replication lag at failure; actual RTO also includes detection, the operator decision, promotion, DNS propagation, and application reconnection. Test both in game days rather than treating the architecture as an SLA by itself.
- The module does **not** automatically promote a region based only on a failed health check. A network partition or slow writer is not proof of regional failure, and an unsafe promotion can cause data loss. RDS failure events and regional alarms go to separate SNS topics; wire both to a 24x7 on-call destination and follow the runbook below.

The recovery cluster is always running (not a snapshot-restore or newly provisioned standby), and its security-group ingress is created up front so recovery does not depend on the failed region or a last-minute network change.

## Defaults owned by the module

- Aurora PostgreSQL 16.4, provisioned `db.r6g.large` instances, two per region.
- Encryption at rest with separate rotating customer-managed KMS keys in each region; no public instances.
- TLS enforced by `rds.force_ssl`, SCRAM password encryption, and IAM database authentication enabled in both regions.
- An RDS-generated master password stored in Secrets Manager with a customer-managed key and 30-day managed rotation. No password variable or state value is accepted by this module.
- 35-day automated backups, final snapshots, deletion protection, maintenance/backup windows, and tags copied to snapshots.
- Enhanced monitoring every 60 seconds, Performance Insights, PostgreSQL logs encrypted and retained for one year, CPU/memory/RPO alarms, and RDS cluster event subscriptions.
- `pg_stat_statements`, slow-statement logging (one second and longer), DDL/connection/lock/temp-file logging, and a five-minute idle-in-transaction timeout.
- PostgreSQL port 5432 only, with ingress exclusively from explicitly approved EKS security groups or CIDRs. There are no module-created broad egress or public ingress rules.

## Required service-specific inputs

Supply `name`, both VPC IDs, and at least one application security group or CIDR per region. By default, the module discovers all subnets in each VPC tagged `tier = database`. The discovered/provided subnet set must contain at least two subnets; use subnets in different AZs. `primary_db_subnet_ids` and `secondary_db_subnet_ids` are explicit overrides, not an additional requirement.

```hcl
name               = "checkout-prod"
database_name      = "checkout"
primary_region     = "us-east-1"
secondary_region   = "us-west-2"
primary_vpc_id     = "vpc-..."
secondary_vpc_id   = "vpc-..."

primary_application_security_group_ids   = ["sg-..."]
secondary_application_security_group_ids = ["sg-..."]

alarm_email_endpoints = ["dba-oncall@example.com"]
tags = {
  Environment = "apps-prod"
}
```

`minimal.tfvars` uses placeholder network IDs solely to make the smallest instantiation deterministic in a plan. Replace all placeholders before applying.

## EKS/IAM connection contract

Network access and IAM database authentication are separate controls. The pod's IAM role needs a policy like the following, scoped to the intended database user and cluster resource ID (available from the RDS console/API):

```json
{
  "Effect": "Allow",
  "Action": "rds-db:connect",
  "Resource": "arn:aws:rds-db:REGION:ACCOUNT:dbuser:CLUSTER_RESOURCE_ID/app_service"
}
```

Using an administrative connection from `master_user_secret_arn`, create a separate least-privilege PostgreSQL role for the service:

```sql
CREATE ROLE app_service LOGIN;
GRANT rds_iam TO app_service;
-- Grant only the schemas/tables and operations this service requires.
```

The application requests an IAM authentication token with `aws rds generate-db-auth-token`, uses it as the PostgreSQL password for `app_service`, and connects with TLS `verify-full` and the current AWS RDS CA bundle. IAM tokens are valid for 15 minutes; generate a fresh token for each new connection. Do not use the master user for application traffic. Create/grant the same application role before an emergency so the secondary already contains it through replication.

## Regional failure runbook

1. **Confirm scope.** Check AWS Health/RDS events and service telemetry. Distinguish an instance/AZ problem (Aurora handles this in-region) from a regional writer/control-plane failure.
2. **Check recovery health and RPO.** In the secondary region inspect `AuroraGlobalDBRPOLag`, CPU, memory, and replication status. Unplanned failover can lose unreplicated writes; do not describe it as zero-data-loss.
3. **Invoke managed failover** against the healthy target. The initial configuration's exact command is in `unplanned_failover_command`; its general form is:

   ```sh
   aws rds failover-global-cluster \
     --region SECONDARY_REGION \
     --global-cluster-identifier GLOBAL_ID \
     --target-db-cluster-identifier TARGET_CLUSTER_ARN
   ```

4. **Wait for the target to become writer.** Confirm `GlobalClusterMembers[].IsWriter`, cluster/instance availability, and successful write/read probes. Managed failover makes the old primary a secondary when it returns, avoiding two writable clusters.
5. **Reconnect applications.** Keep using `global_writer_endpoint`; refresh DNS and recreate pools. Verify writes, IAM authentication, replication lag, and the payment/application reconciliation path before declaring recovery complete.
6. **Restore operational redundancy.** Subscribe to the now-primary region's SNS topic and investigate the impaired region. Do not immediately fail back. After both regions are healthy, use the zero-data-loss `switchover-global-cluster` operation if a planned return is required. Build commands afresh after any failover because the original primary/secondary direction has changed.

For planned drills, use `planned_switchover_command`; switchover requires both regions to be healthy and waits for replication to catch up. Test DNS behavior and reconnect logic during every drill.

## Applying and destroying

```sh
tofu init
tofu validate
tofu plan -var-file=minimal.tfvars
tofu apply -var-file=YOUR_ENVIRONMENT.tfvars
```

To decommission, first take/verify any required manual snapshot, then set `deletion_protection = false` and apply before destroying. Final snapshots have deterministic names (`NAME-primary-final` and `NAME-secondary-final`), so remove or rename old snapshots before repeating a create/destroy cycle. Destruction and rotation of KMS keys remain subject to the 30-day key deletion window.
