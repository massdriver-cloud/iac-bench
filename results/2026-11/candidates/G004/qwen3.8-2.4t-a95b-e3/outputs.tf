# ---------------------------------------------------------------------------
# Global database
# ---------------------------------------------------------------------------

output "global_cluster_identifier" {
  description = "Identifier of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

# ---------------------------------------------------------------------------
# Primary region (writable today)
# ---------------------------------------------------------------------------

output "primary_cluster_identifier" {
  description = "Identifier of the primary cluster."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_writer_endpoint" {
  description = "Writer endpoint of the primary cluster. Point the service here for reads and writes."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint of the primary cluster (load-balanced across readers)."
  value       = aws_rds_cluster.primary.reader_endpoint
}

# ---------------------------------------------------------------------------
# Secondary region (standby today; writable after promotion)
# ---------------------------------------------------------------------------

output "secondary_cluster_identifier" {
  description = "Identifier of the secondary cluster."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary cluster. Use this ARN as the failover target in the disaster-recovery runbook (see README.md)."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_writer_endpoint" {
  description = "Writer endpoint of the secondary cluster. Becomes the service's read/write endpoint after a regional failover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint of the secondary cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

# ---------------------------------------------------------------------------
# Connection details
# ---------------------------------------------------------------------------

output "database_name" {
  description = "Logical PostgreSQL database in the cluster."
  value       = local.database_name
}

output "port" {
  description = "TCP port the cluster listens on."
  value       = var.port
}

output "master_username" {
  description = "Master username."
  value       = aws_rds_cluster.primary.master_username
}

output "master_credentials_secret_arn" {
  description = "Secrets Manager secret holding the master credentials (only when the RDS-managed password is used, i.e. var.master_password is null)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

# ---------------------------------------------------------------------------
# Supporting resources (for wiring services and on-call tooling)
# ---------------------------------------------------------------------------

output "primary_security_group_id" {
  description = "Security group attached to the primary cluster instances."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group attached to the secondary cluster instances."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "KMS key encrypting the primary cluster's storage."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "KMS key encrypting the secondary cluster's storage."
  value       = aws_kms_key.secondary.arn
}

output "monitoring_role_arn" {
  description = "IAM role used for Enhanced Monitoring."
  value       = aws_iam_role.rds_monitoring.arn
}
