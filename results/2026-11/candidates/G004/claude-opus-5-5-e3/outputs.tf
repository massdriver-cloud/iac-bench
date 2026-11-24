output "global_cluster_id" {
  description = "Aurora global cluster identifier (used for switchover/failover)."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "Global writer endpoint; follows the writer across regions after switchover/failover. Applications should write through this."
  value       = aws_rds_global_cluster.this.endpoint
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary-region cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint of the primary-region cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "Cluster endpoint of the secondary-region cluster (becomes writer after promotion)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint of the secondary-region cluster, for local reads in that region."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "database_name" {
  description = "Initial database name."
  value       = local.database_name
}

output "iam_db_username" {
  description = "Database role applications connect as via IAM authentication."
  value       = local.iam_db_user
}

output "iam_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect on both clusters; attach to service roles."
  value       = aws_iam_policy.connect.arn
}

output "master_secret_arn" {
  description = "Secrets Manager secret holding break-glass master credentials (replicated to the secondary region)."
  value       = aws_secretsmanager_secret.master.arn
}

output "security_group_ids" {
  description = "Aurora security group per region."
  value = {
    (var.primary_region)   = aws_security_group.primary.id
    (var.secondary_region) = aws_security_group.secondary.id
  }
}

output "kms_key_arns" {
  description = "Customer-managed KMS key per region."
  value = {
    (var.primary_region)   = aws_kms_key.primary.arn
    (var.secondary_region) = aws_kms_key.secondary.arn
  }
}
