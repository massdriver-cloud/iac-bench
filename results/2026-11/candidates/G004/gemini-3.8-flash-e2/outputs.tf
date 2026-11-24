# Outputs for service configuration and integration

output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.global.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.global.arn
}

output "primary_cluster_id" {
  description = "Identifier of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint for the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint for the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_cluster_port" {
  description = "Database listening port (5432)."
  value       = aws_rds_cluster.primary.port
}

output "primary_cluster_resource_id" {
  description = "Resource ID of the primary cluster, used in IAM database authentication."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "secondary_cluster_id" {
  description = "Identifier of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_cluster_resource_id" {
  description = "Resource ID of the secondary cluster, used in IAM database authentication."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "database_name" {
  description = "Name of the default database created in the cluster."
  value       = local.database_name
}

output "master_username" {
  description = "Master username for database administration."
  value       = aws_rds_cluster.primary.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret storing the managed master user password."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
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
  description = "KMS CMK ARN used for encryption at rest in the primary region."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "KMS CMK ARN used for encryption at rest in the secondary region."
  value       = aws_kms_key.secondary.arn
}

output "iam_db_connect_policy_arn" {
  description = "IAM policy ARN to attach to EKS service account IAM roles for database authentication."
  value       = aws_iam_policy.db_connect.arn
}

output "primary_cloudwatch_log_group" {
  description = "CloudWatch Log Group name for primary PostgreSQL log exports."
  value       = aws_cloudwatch_log_group.primary_postgresql.name
}

output "secondary_cloudwatch_log_group" {
  description = "CloudWatch Log Group name for secondary PostgreSQL log exports."
  value       = aws_cloudwatch_log_group.secondary_postgresql.name
}
