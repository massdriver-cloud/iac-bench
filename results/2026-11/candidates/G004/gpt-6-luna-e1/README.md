# Aurora PostgreSQL Global Database

Standalone OpenTofu root module for a production Aurora PostgreSQL database in two AWS regions. It creates an Aurora Global Database with a multi-AZ primary and a pre-provisioned secondary cluster, so the secondary has compute capacity available for promotion rather than needing to be built during an incident.

## What this module configures

- Aurora PostgreSQL Global Database, initially writable in `primary_region` and replicated to `secondary_region`.
- Two DB instances by default in each region. The primary-region pair provides local writer failover; the secondary instances are warm failover capacity.
- Database subnet groups from subnets in each supplied VPC tagged `tier=database`. Optionally, explicit subnet ID sets can be supplied; this is useful for plan-only examples and controlled subnet selection. In either case, at least two subnet IDs per region are required, and the actual subnets must cover at least two AZs.
- Private network access only: no public DB instances, and TCP/5432 ingress only from the supplied EKS security groups.
- Region-specific customer-managed KMS keys with rotation for cluster storage and Performance Insights.
- RDS-managed master password in Secrets Manager (no password variable/state value), TLS enforced by cluster parameter groups, IAM DB authentication enabled, PostgreSQL connection logs exported to CloudWatch, and 35-day backups by default.
- Inline `rds-db:connect` policies on the supplied existing EKS IAM roles for the configured IAM database username in both regional clusters.
- Deletion protection and OpenTofu `prevent_destroy` on the global and regional clusters.

## Inputs and prerequisites

The AWS credentials must be able to provision RDS, EC2/VPC security groups and subnet groups, KMS, CloudWatch Logs, and IAM role inline policies in both regions. The two regional VPCs and EKS security groups/roles must already exist. The IAM role names refer to roles in the account selected by the AWS credentials.

For automatic subnet discovery, leave `primary_database_subnet_ids` and `secondary_database_subnet_ids` empty. The module filters by VPC ID and `tier=database`. If explicit subnet IDs are provided, the caller is responsible for supplying only the private, database-tier subnets in the corresponding VPC; AWS will reject subnet groups that do not meet Aurora's AZ requirements.

Set `engine_version` to an Aurora PostgreSQL version available in both selected regions. The default is `16.4`; an engine-family update can require parameter group replacement and should be handled as a controlled change.

## IAM-authenticated application users

The module grants IAM principals permission to request a database authentication token, but PostgreSQL still requires a login with the `rds_iam` role and appropriate database/schema/table privileges. Use an operator-controlled bootstrap process with the generated master secret to create/configure the login named by `iam_database_username` (for example, `CREATE USER <iam_database_username> WITH LOGIN; GRANT rds_iam TO <iam_database_username>;` and the narrowly scoped database/object grants required by the service). Do not use the master account for application traffic. SQL user/grant management is deliberately not performed by OpenTofu.

## Regional failover is an operational action

Aurora Global Database normally replicates with very low lag and the secondary cluster is pre-provisioned, but **this module does not automatically promote the secondary or redirect application traffic**. An operator or a separately tested incident automation must detect the primary-region failure, invoke the appropriate Aurora Global Database failover operation, and route/reconnect EKS workloads to the promoted cluster. A regional failover can lose writes if the latest changes have not reached the secondary; Global Database replication is asynchronous, so neither a particular RPO nor an RTO is guaranteed by infrastructure configuration alone. Establish and regularly exercise the failover, application endpoint discovery, and recovery runbooks before relying on this for a production SLO.

Use the outputs for the primary and secondary regional endpoints and the global cluster identifier. After failover, ensure clients resolve/use the promoted region's writer endpoint and refresh pooled connections. Coordinate failback separately; do not use a routine OpenTofu apply as a failover mechanism.
