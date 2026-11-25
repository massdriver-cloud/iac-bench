output "global_cluster_identifier" {
  description = "Identifier passed to the managed global switchover/failover APIs."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "global_writer_endpoint" {
  description = "Regional-failure-safe writer DNS name. Applications should use this endpoint and reconnect on failover."
  value       = aws_rds_global_cluster.this.endpoint
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = local.database_name
}

output "database_port" {
  description = "PostgreSQL listener port."
  value       = var.port
}

output "iam_database_user_name" {
  description = "Database role applications authenticate as with IAM. Grant rds_iam to this role before application use."
  value       = var.iam_database_user_name
}

output "application_connect_policy_arn" {
  description = "Least-privilege IAM policy covering rds-db:connect to both regional cluster resource IDs."
  value       = aws_iam_policy.application_connect.arn
}

output "primary" {
  description = "Primary regional connection and operations attributes."
  value = {
    region                 = var.primary_region
    cluster_identifier     = aws_rds_cluster.primary.id
    cluster_arn            = aws_rds_cluster.primary.arn
    writer_endpoint        = aws_rds_cluster.primary.endpoint
    reader_endpoint        = aws_rds_cluster.primary.reader_endpoint
    security_group_id      = aws_security_group.primary.id
    kms_key_arn            = aws_kms_key.primary.arn
    master_user_secret_arn = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
    operations_topic_arn   = aws_sns_topic.primary_operations.arn
  }
}

output "secondary" {
  description = "Secondary regional connection, failover-target, and operations attributes."
  value = {
    region               = var.secondary_region
    cluster_identifier   = aws_rds_cluster.secondary.id
    cluster_arn          = aws_rds_cluster.secondary.arn
    reader_endpoint      = aws_rds_cluster.secondary.reader_endpoint
    security_group_id    = aws_security_group.secondary.id
    kms_key_arn          = aws_kms_key.secondary.arn
    operations_topic_arn = aws_sns_topic.secondary_operations.arn
  }
}
