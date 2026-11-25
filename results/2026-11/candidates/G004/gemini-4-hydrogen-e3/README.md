# Production Aurora PostgreSQL Global Database Module

Reusable OpenTofu root module for provisioning customer-facing, PCI/PII-sensitive PostgreSQL databases on Amazon Aurora Global Database across two US AWS regions.

## Architecture & Key Design Decisions

- **Cross-Region Disaster Recovery (RPO < few seconds, RTO < minutes)**:
  - Uses `aws_rds_global_cluster` (`aurora-postgresql`) with continuous storage-level replication between `primary_region` (`us-east-1`) and `secondary_region` (`us-west-2`).
  - Deploys `2` provisioned Multi-AZ instances (`db.r6g.large` by default) in **both** regions (`primary_instance_count = 2`, `secondary_instance_count = 2`). Intra-region AZ failures fail over locally without cross-region impact, and upon a regional failover the secondary region already has warm Multi-AZ compute ready to serve writes immediately.
- **EKS IAM Authentication**:
  - Enables `iam_database_authentication_enabled = true` on both regional clusters.
  - Creates an IAM policy (`iam_connect_policy_arn`) scoped to `rds-db:connect` for both primary and secondary `cluster_resource_id`s, and optionally attaches it to `eks_iam_role_names`.
  - Break-glass master credentials are automatically managed and rotated in AWS Secrets Manager (`manage_master_user_password = true`) encrypted with the primary KMS key.
- **Network Discovery & Isolation**:
  - Automatically resolves the network team's `apps-<environment>` VPCs (`apps-staging` / `apps-prod`) and private database subnets tagged `tier = database` in both regions, verifying at least 2 subnets per region.
  - Creates least-privilege security groups per region with zero default ingress (wildcard CIDRs `0.0.0.0/0` and `::/0` are rejected by input validation) and no unrestricted egress.
- **Encryption, Hardening & Auditability (Customer & Payment Data)**:
  - Dedicated customer-managed KMS keys with automatic annual rotation in each region encrypt cluster storage, snapshots, Performance Insights, Secrets Manager credentials, and CloudWatch log groups.
  - Custom cluster & instance parameter groups enforce TLS (`rds.force_ssl = 1`), `scram-sha-256` password encryption, `pg_stat_statements`, `pgaudit` (`ddl,role,write`), connection/disconnection logging, slow query logging, and idle-in-transaction timeouts.
  - Pre-creates KMS-encrypted CloudWatch Log Groups with `365`-day default retention and configures CloudWatch Alarms including `AuroraGlobalDBRPOLag` (default 5000 ms threshold) in the secondary region.
  - Production safety defaults: `deletion_protection = true`, `skip_final_snapshot = false`, `backup_retention_period = 35`, `publicly_accessible = false`, `apply_immediately = false`, `allow_major_version_upgrade = false`.

## Minimal Usage

```hcl
service_name  = "checkout"
environment   = "prod"
database_name = "checkout"
```

## Post-Provisioning IAM Database Bootstrap

After applying, connect once using the break-glass master secret (`primary_master_user_secret_arn`) over TLS and grant `rds_iam` to your service's PostgreSQL role(s) (`iam_database_users`):

```sql
CREATE USER checkout_app WITH LOGIN;
GRANT rds_iam TO checkout_app;
-- Grant schema/table privileges as required by the service.
```
