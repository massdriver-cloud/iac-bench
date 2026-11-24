# ---------------------------------------------------------------------------
# Outputs
# ---------------------------------------------------------------------------

output "global_cluster_identifier" {
  description = "Global database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "Global database ARN."
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_identifier" {
  description = "Primary cluster identifier."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "Primary cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "primary_writer_endpoint" {
  description = "Primary cluster writer endpoint (DNS)."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary cluster reader endpoint (DNS)."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_identifier" {
  description = "DR cluster identifier."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "DR cluster ARN."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_writer_endpoint" {
  description = "DR cluster endpoint. Becomes the writer after a regional failover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "DR cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.primary.port
}

output "database_name" {
  description = "Initial database name."
  value       = local.database_name
}

output "master_username" {
  description = "Master database user (also the IAM database-auth user)."
  value       = var.master_username
}

output "master_password_secret_arn" {
  description = "Secrets Manager secret holding the master password (primary region). Prefer IAM database authentication from workloads."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "iam_auth_policy_arn" {
  description = "IAM policy granting rds-db:connect as the master user on both clusters; attach it to the service's EKS IAM roles."
  value       = aws_iam_policy.iam_db_auth.arn
}

output "primary_region" {
  description = "Region of the primary cluster."
  value       = var.primary_region
}

output "secondary_region" {
  description = "Region of the DR cluster."
  value       = var.secondary_region
}

output "primary_security_group_id" {
  description = "Security group protecting the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group protecting the DR cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "KMS key encrypting the primary cluster."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "KMS key encrypting the DR cluster."
  value       = aws_kms_key.secondary.arn
}

output "failover_command" {
  description = <<-EOT
    Regional-failover runbook command: promotes the DR cluster to writer.
    Completes in about a minute; replication lag is typically < 1 second,
    so at most a few seconds of writes are lost. Point the service at the
    DR cluster's writer endpoint afterwards.
  EOT
  value       = "aws rds global-cluster failover --global-cluster-identifier ${aws_rds_global_cluster.this.arn} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}
