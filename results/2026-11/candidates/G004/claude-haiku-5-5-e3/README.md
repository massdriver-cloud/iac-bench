# aurora-postgres-global

Production Aurora PostgreSQL Global Database for one service, spanning two US regions.

## What it builds

- One Aurora Global Database with a **primary** regional cluster (writer) in `primary_region`
  and a **secondary** regional cluster in `secondary_region`. Storage replicates from the
  primary to the secondary, typically in under a second. The secondary can be promoted.
- Each region's cluster runs `instance_count_per_region` instances across the private
  subnets tagged `tier = database` in that region's `apps-<environment>` VPC.
- Per-region customer-managed KMS keys (rotation on). Storage, backups, Performance Insights
  and the master password secret are encrypted with the key in their own region.
- Master password generated and held by RDS in Secrets Manager (never in state or in code).
- IAM database authentication. Applications use `rds-db:connect`, not passwords.
  Attach `db_connect_policy_arn` to a role, or list the roles in `app_iam_role_names`.
- TLS enforced (`rds.force_ssl`), idle-in-transaction timeout, slow-query logging.
- PostgreSQL logs to CloudWatch Logs with retention set (365 days by default).
- Backups: 35 days by default, with point-in-time recovery. Final snapshots on destroy.
- Deletion protection on by default.
- Alarm on replication lag to the secondary above 5 seconds for 3 minutes (the RPO signal).

## Recovery objectives

- **RPO:** a few seconds. Equal to the replication lag at the moment of failure, which the
  `AuroraGlobalDBReplicationLag` alarm tracks.
- **RTO:** about a minute to promote, plus the time to switch application endpoints.

## Assumptions

- The network team's VPCs are named `apps-staging` / `apps-prod` (Name tag) in both regions,
  with database subnets tagged `tier = database` in at least two AZs.
- The two VPCs can reach each other (peering or Transit Gateway) so that a service in
  the secondary region can reach the writer in the primary region before a failover.
  This module does not create that connectivity.
- Applications reach the database over the network via the security groups given in
  `allowed_security_group_ids` (preferred) or `allowed_cidr_blocks`, both in each region.

## Failover runbook (primary region lost)

1. **Promote the secondary.** Run this from any machine with AWS access:
   ```
   aws rds failover-global-cluster \
     --global-cluster-identifier <global_cluster_identifier> \
     --target-db-cluster-identifier <secondary cluster ARN> \
     --region <secondary_region>
   ```
   Use the `secondary.cluster_id` output to build the ARN. This is an unplanned failover, so
   the old primary is left behind and is not reachable.
2. **Point the writer name at the new writer.** Set `writer_region = "secondary"` and apply.
   If the primary region's state can't be refreshed, apply with
   `-refresh=false -target=aws_route53_record.writer`, or update the CNAME by hand and
   reconcile state later.
3. **Confirm the services work.** Services in the secondary region write to the local
   cluster endpoint. Check the `AuroraGlobalDBReplicationLag` alarm is not counting down,
   and check that application error rates fall.
4. **Recover the old region.** When the primary region returns, its cluster rejoins as a
   secondary of the new primary. Do not fail back until the lag is back under 5 seconds
   for a while. To return the writer to the original region, do a planned switchover with
   `aws rds switchover-global-cluster` (zero data loss), then set `writer_region = "primary"`
   and apply.

## Inputs

See `variables.tf`. Required: `service_name`, `environment`, `primary_region`,
`secondary_region`. Everything else has a default that is safe for production.

## Outputs

See `outputs.tf`: cluster IDs, writer and reader endpoints, KMS key ARNs, master secret ARN,
and the IAM connect policy ARN.
