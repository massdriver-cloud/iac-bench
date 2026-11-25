output "global_cluster_id" {
  description = "Aurora Global Database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "primary_region" {
  description = "Region currently configured as the writer region (the one this module created as primary). After a failover, check the live writer with: aws rds describe-global-clusters."
  value       = var.primary_region
}

output "primary_writer_endpoint" {
  description = "Writer endpoint in the primary region. Use this for normal operation."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Read-only endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary cluster; the target of a failover or switchover."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_writer_endpoint" {
  description = "Endpoint of the secondary cluster in the secondary region. Read-only until promoted; becomes the writer after a failover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Read-only endpoint in the secondary region."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.primary.port
}

output "database_name" {
  description = "Initial database name."
  value       = var.database_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN holding the managed master password (rotated by RDS)."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "db_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for iam_database_users in both regions. Attach to service roles that are not listed in application_role_names."
  value       = aws_iam_policy.db_connect.arn
}

output "kms_key_arn_primary" {
  description = "KMS key encrypting the primary cluster."
  value       = aws_kms_key.primary.arn
}

output "kms_key_arn_secondary" {
  description = "KMS key encrypting the secondary cluster."
  value       = aws_kms_key.secondary.arn
}

output "failover_runbook" {
  description = "Commands for a planned switchover (drill, zero data loss) and an unplanned regional failover (data loss bounded by replication lag)."
  value = {
    switchover_drill   = "aws rds switchover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.primary_region}"
    unplanned_failover = "aws rds failover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.secondary_region}"
    after_failover     = "Point services at the new writer (the secondary cluster endpoint). Then run `tofu apply` with the same inputs; see README.md, section 'Regional failover'."
  }
}
