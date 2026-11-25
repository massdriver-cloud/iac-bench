output "global_cluster_id" {
  description = "The ID of the Aurora Global Database cluster"
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "The ARN of the Aurora Global Database cluster"
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the default database created on the cluster"
  value       = local.database_name
}

output "master_username" {
  description = "Master username for the database"
  value       = var.master_username
}

# Primary Region Outputs
output "primary_cluster_id" {
  description = "The ID of the primary RDS cluster"
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "The ARN of the primary RDS cluster"
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "The writer endpoint for the primary cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "The reader endpoint for the primary cluster"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_security_group_id" {
  description = "The ID of the security group created for the primary cluster"
  value       = aws_security_group.primary.id
}

output "primary_secret_arn" {
  description = "The ARN of the Secrets Manager secret holding primary database credentials"
  value       = aws_secretsmanager_secret.primary.arn
}

output "primary_iam_policy_arn" {
  description = "The ARN of the IAM policy granting rds-db:connect access in primary region"
  value       = aws_iam_policy.db_connect_primary.arn
}

output "primary_kms_key_arn" {
  description = "The ARN of the KMS key used for storage encryption in primary region"
  value       = local.primary_kms_key_arn
}

# Secondary Region Outputs
output "secondary_cluster_id" {
  description = "The ID of the secondary RDS cluster"
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "The ARN of the secondary RDS cluster"
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "The endpoint for the secondary cluster"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "The reader endpoint for the secondary cluster"
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_security_group_id" {
  description = "The ID of the security group created for the secondary cluster"
  value       = aws_security_group.secondary.id
}

output "secondary_secret_arn" {
  description = "The ARN of the Secrets Manager secret holding secondary database credentials"
  value       = aws_secretsmanager_secret.secondary.arn
}

output "secondary_iam_policy_arn" {
  description = "The ARN of the IAM policy granting rds-db:connect access in secondary region"
  value       = aws_iam_policy.db_connect_secondary.arn
}

output "secondary_kms_key_arn" {
  description = "The ARN of the KMS key used for storage encryption in secondary region"
  value       = local.secondary_kms_key_arn
}
