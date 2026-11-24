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
  value       = local.engine_version
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = aws_rds_cluster.primary.database_name
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
  description = "Port for the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.port
}

output "primary_cluster_resource_id" {
  description = "Cluster resource ID (dbi-...) used for IAM database authentication in the primary region."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary Aurora cluster (reference this or add ingress rules for EKS services)."
  value       = aws_security_group.primary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the customer-managed KMS key in the primary region."
  value       = aws_kms_key.primary.arn
}

output "primary_master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret storing the auto-rotated master user credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "secondary_cluster_endpoint" {
  description = "Endpoint for the secondary Aurora PostgreSQL cluster (becomes writer upon failover/switchover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_cluster_port" {
  description = "Port for the secondary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.secondary.port
}

output "secondary_cluster_resource_id" {
  description = "Cluster resource ID (dbi-...) used for IAM database authentication in the secondary region."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "secondary_kms_key_arn" {
  description = "ARN of the customer-managed KMS key in the secondary region."
  value       = aws_kms_key.secondary.arn
}

output "iam_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect for both primary and secondary clusters; attach to EKS service IAM roles."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_database_users" {
  description = "PostgreSQL database roles authorized for IAM authentication."
  value       = local.iam_database_users
}
