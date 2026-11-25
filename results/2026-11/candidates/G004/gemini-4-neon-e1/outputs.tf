################################################################################
# Global Database Outputs
################################################################################

output "global_cluster_id" {
  description = "Identifier of the Aurora PostgreSQL Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_rds_cluster.primary.database_name
}

output "port" {
  description = "TCP port PostgreSQL listens on in both regions."
  value       = aws_rds_cluster.primary.port
}

output "engine_version" {
  description = "Aurora PostgreSQL engine version deployed across both regions."
  value       = aws_rds_global_cluster.this.engine_version
}

################################################################################
# Primary Region Cluster Outputs
################################################################################

output "primary_region" {
  description = "Primary AWS region hosting the active writer cluster."
  value       = var.primary_region
}

output "primary_cluster_id" {
  description = "Cluster identifier in the primary region."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "Cluster ARN in the primary region."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_resource_id" {
  description = "DbiResourceId of the primary cluster (used for IAM rds-db:connect scoping)."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_writer_endpoint" {
  description = "Primary cluster writer DNS endpoint."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary cluster load-balanced reader DNS endpoint."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "primary_vpc_id" {
  description = "Discovered VPC ID ('apps-<env>') in the primary region."
  value       = data.aws_vpc.primary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the primary region Customer Managed KMS key."
  value       = aws_kms_key.primary.arn
}

output "primary_alarm_sns_topic_arn" {
  description = "SNS topic ARN receiving primary region CloudWatch alarms and RDS failover events."
  value       = local.primary_sns_topic_arn
}

################################################################################
# Secondary Region Cluster Outputs (Warm Cross-Region DR)
################################################################################

output "secondary_region" {
  description = "Secondary AWS region hosting the warm Aurora Global Database replica."
  value       = var.secondary_region
}

output "secondary_cluster_id" {
  description = "Cluster identifier in the secondary region."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "Cluster ARN in the secondary region."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_resource_id" {
  description = "DbiResourceId of the secondary cluster (used for IAM rds-db:connect scoping)."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_writer_endpoint" {
  description = "Secondary cluster endpoint (serves writes immediately upon regional failover/switchover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary cluster load-balanced reader DNS endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "secondary_vpc_id" {
  description = "Discovered VPC ID ('apps-<env>') in the secondary region."
  value       = data.aws_vpc.secondary.id
}

output "secondary_kms_key_arn" {
  description = "ARN of the secondary region Customer Managed KMS key."
  value       = aws_kms_key.secondary.arn
}

output "secondary_alarm_sns_topic_arn" {
  description = "SNS topic ARN receiving secondary region CloudWatch alarms (including RPO lag) and RDS events."
  value       = local.secondary_sns_topic_arn
}

################################################################################
# Authentication & Secrets Outputs
################################################################################

output "iam_db_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect to both primary and secondary clusters. Attach to the service's EKS IAM role (IRSA / Pod Identity)."
  value       = aws_iam_policy.db_iam_connect.arn
}

output "iam_db_users" {
  description = "PostgreSQL user names granted rds-db:connect in the IAM policy."
  value       = local.iam_db_users
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed AWS Secrets Manager secret storing the master database credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}
