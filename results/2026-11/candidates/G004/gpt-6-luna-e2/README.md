# Production Aurora PostgreSQL Global Database

This root module provisions an encrypted Aurora PostgreSQL cluster in a primary AWS region and a warm Aurora Global Database secondary in a second region. Each region has a DB subnet group, a security group permitting PostgreSQL only from the supplied EKS client security groups, a cluster parameter group enforcing TLS, and a DB instance. It also enables 35-day backups, RDS-managed administrator credentials in Secrets Manager, IAM database authentication, PostgreSQL log exports, encrypted CloudWatch log groups, deletion protection, and a replication-lag alarm.

## Network inputs

Pass the VPC IDs, at least two subnet IDs per region, and EKS security group IDs for each region. The subnet IDs must refer to the network team's private subnets tagged `tier=database`, in the corresponding VPC and across distinct Availability Zones. AWS validates that relationship during apply; this module intentionally does not create or modify network infrastructure. The EKS security group IDs likewise must belong to the specified VPCs.

`minimal.tfvars` is a syntactically complete example with placeholder network IDs; replace those with actual IDs before applying.

## EKS IAM authentication

Set `iam_role_arns` and `iam_database_users` together to attach a least-privilege `rds-db:connect` policy scoped to those usernames and both regional cluster resource IDs. The PostgreSQL IAM database users and grants are not created by this module: provision them using the administrator secret (or a database migration process). IAM authentication is enabled at the cluster. The IAM role ARNs must belong to one AWS account. For IRSA or EKS Pod Identity, supply the workload role ARN(s), not the cluster's node role unless node-level access is intended.

The RDS-managed master password is encrypted with the primary-region KMS key. Storage, CloudWatch PostgreSQL logs, and the managed database secret use customer-managed KMS keys. KMS key rotation is enabled.

## Regional recovery

The secondary is provisioned as a Global Database secondary with an instance already running, so it can be promoted without provisioning compute after a primary-region outage. Replication is asynchronous; Aurora Global Database is designed for low replication lag, but no infrastructure configuration can guarantee a strict recovery-time or data-loss bound in every outage. The alarm reports when observed secondary replication lag exceeds five seconds; provide `alarm_sns_topic_arns` to notify responders.

Failover is an operational action, not an automatic action performed by this module. Exercise a documented incident runbook that checks replication lag, promotes/fails over the secondary Global Database using the AWS RDS managed failover operation, updates application connectivity to the promoted writer, and later rebuilds the old primary as a secondary. The module outputs both regional endpoints and the global cluster identifier. Validate application reconnection and DNS caching behavior in regular failover drills.

## Operations

Deletion protection is enabled on global and regional clusters. Disable it deliberately before teardown, retain required snapshots, and account for the KMS key deletion window. Pin/approve engine upgrades and keep `postgres_major_version` in sync with `engine_version`. The parameter group enforces SSL (`rds.force_ssl=1`); clients must use TLS.
