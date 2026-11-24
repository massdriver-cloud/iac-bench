output "global_cluster_id" {
  description = "ID of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_id" {
  description = "ID of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret storing master user credentials for primary cluster."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "secondary_cluster_id" {
  description = "ID of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_endpoint" {
  description = "Endpoint for the secondary Aurora cluster (read-only during normal operation)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "Name of the default PostgreSQL database."
  value       = local.db_name
}

output "master_username" {
  description = "Master database username."
  value       = var.master_username
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the primary KMS key used for cluster encryption."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the secondary KMS key used for cluster encryption."
  value       = aws_kms_key.secondary.arn
}

output "primary_iam_auth_policy_arn" {
  description = "ARN of the IAM policy granting IAM DB authentication to the primary cluster."
  value       = aws_iam_policy.db_iam_auth_primary.arn
}

output "secondary_iam_auth_policy_arn" {
  description = "ARN of the IAM policy granting IAM DB authentication to the secondary cluster."
  value       = aws_iam_policy.db_iam_auth_secondary.arn
}
