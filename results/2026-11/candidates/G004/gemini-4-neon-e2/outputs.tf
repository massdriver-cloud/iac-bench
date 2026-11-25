################################################################################
# Global Database Outputs
################################################################################

output "global_cluster_id" {
  description = "Identifier of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = var.database_name
}

output "port" {
  description = "PostgreSQL TCP port."
  value       = var.port
}

output "engine_version" {
  description = "Resolved Aurora PostgreSQL engine version deployed across both regions."
  value       = local.engine_version
}

################################################################################
# Primary Region Cluster Outputs
################################################################################

output "primary_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

output "primary_cluster_id" {
  description = "Primary regional Aurora cluster identifier."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "Primary regional Aurora cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_resource_id" {
  description = "Primary regional Aurora cluster resource ID (used in IAM rds-db:connect ARNs)."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_writer_endpoint" {
  description = "Primary region writer endpoint for EKS services."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary region reader endpoint for read-only traffic."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_security_group_id" {
  description = "Security group ID protecting the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the primary region customer-managed KMS key."
  value       = aws_kms_key.primary.arn
}

output "primary_alerts_sns_topic_arn" {
  description = "SNS topic ARN receiving primary region CloudWatch alarms and RDS events."
  value       = local.primary_sns_topic_arn
}

################################################################################
# Secondary Region Cluster Outputs (Warm Standby / Failover Target)
################################################################################

output "secondary_region" {
  description = "Secondary (failover) AWS region."
  value       = var.secondary_region
}

output "secondary_cluster_id" {
  description = "Secondary regional Aurora cluster identifier."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "Secondary regional Aurora cluster ARN (target ARN for regional failover/switchover)."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_resource_id" {
  description = "Secondary regional Aurora cluster resource ID (used in IAM rds-db:connect ARNs)."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_writer_endpoint" {
  description = "Secondary region cluster endpoint (becomes the active writer endpoint upon failover/promotion)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary region reader endpoint (serves local EKS reads in the secondary region)."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_security_group_id" {
  description = "Security group ID protecting the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "secondary_kms_key_arn" {
  description = "ARN of the secondary region customer-managed KMS key."
  value       = aws_kms_key.secondary.arn
}

output "secondary_alerts_sns_topic_arn" {
  description = "SNS topic ARN receiving secondary region CloudWatch alarms (including RPO replication lag) and RDS events."
  value       = local.secondary_sns_topic_arn
}

################################################################################
# IAM & Break-Glass Credential Outputs
################################################################################

output "iam_db_connect_policy_arn" {
  description = "ARN of the least-privilege IAM policy granting rds-db:connect to BOTH regional clusters for EKS service IAM roles."
  value       = aws_iam_policy.db_connect.arn
}

output "db_iam_usernames" {
  description = "PostgreSQL database role names authorized in the IAM rds-db:connect policy."
  value       = local.db_iam_usernames
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed AWS Secrets Manager secret containing break-glass master credentials (encrypted with primary KMS CMK)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}
