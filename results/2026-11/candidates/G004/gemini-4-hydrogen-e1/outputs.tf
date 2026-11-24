output "global_cluster_id" {
  description = "Identifier of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "engine_version" {
  description = "Resolved Aurora PostgreSQL engine version."
  value       = aws_rds_global_cluster.this.engine_version
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = local.database_name
}

output "port" {
  description = "PostgreSQL TCP port."
  value       = var.port
}

output "primary_cluster_id" {
  description = "Primary Aurora cluster identifier."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "Primary Aurora cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "primary_writer_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Load-balanced reader endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "Secondary Aurora cluster identifier."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "Secondary Aurora cluster ARN."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_endpoint" {
  description = "Cluster endpoint for the secondary Aurora cluster (becomes writable upon regional failover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the primary region KMS key."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the secondary region KMS key."
  value       = aws_kms_key.secondary.arn
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret holding the RDS-managed master user password."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "master_secret_read_policy_arn" {
  description = "ARN of the IAM policy granting least-privilege read access to the master credentials secret for migration/admin roles."
  value       = aws_iam_policy.master_secret_read.arn
}

output "iam_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect in both primary and secondary regions for EKS service roles."
  value       = aws_iam_policy.db_connect.arn
}

output "primary_sns_topic_arn" {
  description = "SNS topic ARN receiving primary region Aurora alerts and RDS events."
  value       = local.primary_sns_topic_arn
}

output "secondary_sns_topic_arn" {
  description = "SNS topic ARN receiving secondary region Aurora alerts, replication lag alarms, and RDS events."
  value       = local.secondary_sns_topic_arn
}
