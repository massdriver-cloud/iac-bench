output "global_cluster_id" {
  description = "The ID of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "The ARN of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_id" {
  description = "The cluster identifier of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "The ARN of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "The writer endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "The reader endpoint for the primary Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "The cluster identifier of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "The ARN of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "The endpoint for the secondary Aurora cluster (becomes writer after failover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "The reader endpoint for the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "The name of the database created on the primary cluster."
  value       = aws_rds_cluster.primary.database_name
}

output "database_port" {
  description = "The port on which the database accepts connections."
  value       = var.port
}

output "master_username" {
  description = "The master username for PostgreSQL connections."
  value       = aws_rds_cluster.primary.master_username
}

output "master_user_secret_arn" {
  description = "The Amazon Resource Name (ARN) of the Secrets Manager secret storing the master user password."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "primary_security_group_id" {
  description = "Security group ID controlling access to the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID controlling access to the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "The ARN of the KMS key encrypting the primary Aurora cluster and its backups."
  value       = local.primary_kms_key_arn
}

output "secondary_kms_key_arn" {
  description = "The ARN of the KMS key encrypting the secondary Aurora cluster."
  value       = local.secondary_kms_key_arn
}

output "iam_connect_policy_arn" {
  description = "The ARN of the IAM policy granting EKS service roles rds-db:connect permissions via IAM database auth."
  value       = aws_iam_policy.rds_connect.arn
}

output "primary_instance_ids" {
  description = "List of instance identifiers in the primary region cluster."
  value       = aws_rds_cluster_instance.primary[*].id
}

output "secondary_instance_ids" {
  description = "List of instance identifiers in the secondary region cluster."
  value       = aws_rds_cluster_instance.secondary[*].id
}
