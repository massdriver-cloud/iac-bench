# ------------------------------------------------------------------------------
# Aurora Global Database
# ------------------------------------------------------------------------------

output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "global_cluster_resource_id" {
  description = "AWS-generated immutable resource ID of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.global_cluster_resource_id
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = local.database_name
}

output "port" {
  description = "PostgreSQL TCP port."
  value       = var.port
}

output "master_username" {
  description = "Master administrator username (password is managed and rotated in AWS Secrets Manager)."
  value       = var.master_username
}

# ------------------------------------------------------------------------------
# EKS IAM Authentication & Monitoring
# ------------------------------------------------------------------------------

output "iam_db_connect_policy_arn" {
  description = "IAM policy ARN granting rds-db:connect for both primary and secondary clusters. Attach to EKS IRSA / Pod Identity service roles."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_auth_db_users" {
  description = "PostgreSQL usernames granted IAM database authentication via iam_db_connect_policy_arn."
  value       = local.iam_auth_db_users
}

output "enhanced_monitoring_role_arn" {
  description = "IAM role ARN used by RDS Enhanced Monitoring across both regions (null if monitoring_interval is 0)."
  value       = try(aws_iam_role.enhanced_monitoring[0].arn, null)
}

# ------------------------------------------------------------------------------
# Primary Regional Cluster
# ------------------------------------------------------------------------------

output "primary_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

output "primary_vpc_id" {
  description = "Discovered VPC ID for apps-<environment> in the primary region."
  value       = data.aws_vpc.primary.id
}

output "primary_cluster_id" {
  description = "Primary Aurora cluster identifier."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "Primary Aurora cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_resource_id" {
  description = "Primary Aurora cluster resource ID."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_writer_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_master_user_secret_arn" {
  description = "AWS Secrets Manager secret ARN holding the RDS-managed master credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "primary_security_group_id" {
  description = "Security group ID for the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "primary_kms_key_arn" {
  description = "Customer-managed KMS key ARN in the primary region."
  value       = aws_kms_key.primary.arn
}

output "primary_alerts_sns_topic_arn" {
  description = "KMS-encrypted SNS topic ARN for primary cluster alarms and RDS events."
  value       = aws_sns_topic.primary_alerts.arn
}

output "primary_log_group_name" {
  description = "CloudWatch Log Group name for primary PostgreSQL and pgaudit logs."
  value       = aws_cloudwatch_log_group.primary_postgresql.name
}

# ------------------------------------------------------------------------------
# Secondary Regional Cluster (Disaster Recovery / Regional Failover)
# ------------------------------------------------------------------------------

output "secondary_region" {
  description = "Secondary AWS region hosting the warm Aurora Global Database replica."
  value       = var.secondary_region
}

output "secondary_vpc_id" {
  description = "Discovered VPC ID for apps-<environment> in the secondary region."
  value       = data.aws_vpc.secondary.id
}

output "secondary_cluster_id" {
  description = "Secondary Aurora cluster identifier."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "Secondary Aurora cluster ARN."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_resource_id" {
  description = "Secondary Aurora cluster resource ID."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_writer_endpoint" {
  description = "Writer endpoint for the secondary Aurora cluster (active immediately upon regional failover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_security_group_id" {
  description = "Security group ID for the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "secondary_kms_key_arn" {
  description = "Customer-managed KMS key ARN in the secondary region."
  value       = aws_kms_key.secondary.arn
}

output "secondary_alerts_sns_topic_arn" {
  description = "KMS-encrypted SNS topic ARN for secondary cluster alarms and RDS events."
  value       = aws_sns_topic.secondary_alerts.arn
}

output "secondary_log_group_name" {
  description = "CloudWatch Log Group name for secondary PostgreSQL and pgaudit logs."
  value       = aws_cloudwatch_log_group.secondary_postgresql.name
}
