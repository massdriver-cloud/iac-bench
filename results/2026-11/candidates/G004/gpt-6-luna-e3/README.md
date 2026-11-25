# Production Aurora PostgreSQL Global Database

This root module deploys an encrypted Aurora PostgreSQL Global Database in two AWS regions. It discovers the VPC named by `environment` in each region and uses all subnets tagged `tier=database`. It creates a private security group in each VPC; inbound PostgreSQL access is limited to the explicitly supplied EKS security groups. It provisions two Aurora Serverless v2 instances per region by default, regional KMS keys, encrypted PostgreSQL log groups, enhanced monitoring, IAM database authentication, SSL enforcement, and 35-day automated backups/PITR.

## Inputs to set for a service

At minimum, set `service_name`, `environment`, `database_name`, and `master_username`. Set the primary and secondary EKS security-group ID lists for their respective regions before routing application traffic. `iam_db_user_roles` can grant `rds-db:connect` to named IAM roles for database usernames. The SQL users still need to be created and granted `rds_iam` in PostgreSQL; the managed master secret is for tightly controlled bootstrap/admin use, not application connections. Region and capacity settings have safe defaults and can be overridden.

`minimal.tfvars` is an example that plans against the platform's `apps-prod` VPCs. It intentionally supplies no EKS security groups, so its database security groups have no inbound PostgreSQL rules. Add real EKS group IDs for a usable service deployment.

## Resilience and failover

The cross-region Aurora Global Database continuously replicates storage asynchronously; normal replication lag is typically under a second, but AWS does not guarantee a fixed maximum RPO during every regional failure. Each region has multiple instances so local instance/AZ failures can fail over within the region. Both clusters are kept available so a secondary can be promoted during a regional incident.

A Global Database is **not automatically promoted by this module**. Regional failover requires the on-call operator or a separately operated automation system to perform the AWS Aurora Global Database managed/unplanned failover, verify the new writer, and direct applications to the promoted region. The primary and secondary writer endpoint outputs are regional endpoints; promotion does not make the old primary endpoint globally follow the new writer. Application routing/configuration and EKS connectivity in both regions must therefore be prepared ahead of time. Establish and regularly exercise the incident runbook to meet the service's RTO/RPO objective; failover time and lost writes depend on replication lag and the incident procedure.

Deletion protection is enabled on the global database and both clusters. Planned maintenance is not applied immediately; major version upgrades are not enabled. Review the AWS Aurora PostgreSQL release and Serverless v2 regional availability before overriding the pinned engine version/family.
