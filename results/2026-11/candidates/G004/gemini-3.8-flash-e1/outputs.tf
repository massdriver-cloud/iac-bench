output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database cluster"
  value       = aws_rds_global_cluster.main.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database cluster"
  value       = aws_rds_global_cluster.main.arn
}

output "primary_cluster_id" {
  description = "Identifier of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint for the primary Aurora cluster"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_cluster_resource_id" {
  description = "Resource ID of the primary Aurora cluster (used for IAM authentication)"
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "secondary_cluster_id" {
  description = "Identifier of the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Endpoint for the secondary Aurora cluster (becomes writer after failover)"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_cluster_resource_id" {
  description = "Resource ID of the secondary Aurora cluster (used for IAM authentication)"
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "database_name" {
  description = "Name of the default PostgreSQL database"
  value       = local.database_name
}

output "master_username" {
  description = "Master database username"
  value       = var.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret managing the master password"
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "primary_security_group_id" {
  description = "ID of the database security group in the primary region"
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "ID of the database security group in the secondary region"
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the KMS encryption key used in the primary region"
  value       = local.primary_kms_key_arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the KMS encryption key used in the secondary region"
  value       = local.secondary_kms_key_arn
}

output "db_connect_iam_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect access for EKS service roles"
  value       = aws_iam_policy.db_connect.arn
}
