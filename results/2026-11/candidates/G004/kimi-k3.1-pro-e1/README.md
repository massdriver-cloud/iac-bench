# Production Aurora PostgreSQL global module

This root module creates an encrypted Aurora PostgreSQL **Global Database** in `us-east-1` and `us-west-2` (both regions are configurable). It discovers the existing `apps-staging` or `apps-prod` VPC by its `Name` tag in each region and all private subnets tagged `tier = database`.

## Availability and data-loss design

- The primary and secondary regional clusters each have at least two provisioned instances, pinned across distinct database-subnet availability zones. Both regions use the same instance class so DR is not a scaled-down standby.
- Aurora storage-level cross-region replication normally has sub-second to seconds-scale lag. The cluster parameter `rds.global_db_rpo` enables Aurora PostgreSQL **managed RPO** (five seconds by default). Aurora throttles primary commits when the configured RPO cannot be maintained; this is an intentional data-durability-versus-write-availability choice.
- The global writer endpoint always resolves to the current global writer after a managed switchover/failover. Applications must use it, use TLS, and reconnect stale connections rather than caching the IP address.
- Managed cross-region failover is deliberately not triggered by health checks in this module. Automatic health-check failover can create a second writer during a network partition. The incident response path is the managed RDS global failover API below; always-running DR capacity and the global endpoint avoid restore or scale-up delays.
- In-region instance failure is handled automatically by Aurora. Thirty-five days of point-in-time recovery, final snapshots, deletion protection, and no public connectivity are the default.

## Application access

There is no default ingress and no master password variable. Supply the EKS application security group IDs independently for each region:

```hcl
application_security_group_ids = {
  primary   = ["sg-0123456789abcdef0"]
  secondary = ["sg-0fedcba9876543210"]
}
application_iam_role_names = ["checkout-eks-primary", "checkout-eks-secondary"]
```

The module attaches an `rds-db:connect` policy containing **both** regional cluster resource IDs to those roles. If roles are managed elsewhere, leave `application_iam_role_names` empty and attach `application_connect_policy_arn` there. After the cluster is available, a database administrator must create the application role and application grants once on the global writer; PostgreSQL role metadata replicates to the secondary:

```sql
CREATE ROLE app LOGIN;
GRANT rds_iam TO app;
-- Grant schema/table privileges appropriate for the service.
```

Applications generate an RDS IAM authentication token for that role and use it as the PostgreSQL password with `sslmode=require`. IAM authentication replaces long-lived application database passwords; the RDS-managed master secret remains available for break-glass administration.

## Regional disaster recovery

The secondary is continuously running and readable. The replication-lag alarm fires at 80% of the configured RPO and treats missing lag data as an alarm. Subscribe incident response to both operations topic ARNs (or set `operations_email_endpoints` and confirm the subscriptions).

For a **regional failure**, use the unplanned managed failover operation from working credentials/network in the secondary region:

```sh
aws rds failover-global-cluster \
  --region <secondary-region> \
  --global-cluster-identifier <global-cluster-identifier> \
  --target-db-cluster-identifier <secondary-cluster-arn> \
  --allow-data-loss
```

The target must be the current secondary cluster. Wait for the command/global cluster status to complete, verify the global writer endpoint resolves to the secondary, and recycle application connections/pools. The command permits loss only up to replication lag at failure; managed RPO is designed to bound committed-write exposure to the configured target. Do not manually promote an old, isolated primary or bring it back as a writer without following the Aurora global reintegration procedure.

For a **planned region move**, use the zero-data-loss managed switchover instead:

```sh
aws rds switchover-global-cluster \
  --region <secondary-region> \
  --global-cluster-identifier <global-cluster-identifier> \
  --target-db-cluster-identifier <secondary-cluster-arn>
```

Exercise switchover and application reconnection regularly. After an unplanned failover, rebuild or re-add the failed region as a replica before considering regional DR restored.

## Smallest instantiation

```sh
tofu init
tofu plan -var-file=minimal.tfvars
```

Only `name` and `environment` are required. Production defaults cover encryption and KMS rotation, IAM database authentication, forced TLS, Performance Insights, enhanced monitoring, PostgreSQL log export with retention, CPU/replication alarms, RDS event notifications, backups, and deletion protection. Email endpoints are optional because confirmed subscriptions and incident routing are usually owned outside an individual service module.
