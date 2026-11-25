output "global_cluster_identifier" {
  description = "Aurora Global Database identifier (use for switchover/failover CLI commands)."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "primary_cluster_identifier" {
  description = "Primary cluster identifier."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_endpoint" {
  description = "Writer endpoint (primary region). Point service write traffic here."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint (primary region), load-balanced across readers."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_identifier" {
  description = "Secondary (DR) cluster identifier."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint in the DR region. Becomes the writer endpoint after a global failover; services in the DR region should read here and switch writes here on failover."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = var.port
}

output "database_name" {
  description = "Initial database name."
  value       = local.database_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-managed master credentials (break-glass access only; grant narrowly)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "db_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect to this database (both regions) for var.iam_database_users. Attach to the service's EKS IRSA role."
  value       = aws_iam_policy.db_connect.arn
}

output "kms_key_arns" {
  description = "Customer-managed KMS keys protecting storage, snapshots, Performance Insights and the master secret, by region."
  value = {
    (var.primary_region)   = aws_kms_key.primary.arn
    (var.secondary_region) = aws_kms_key.secondary.arn
  }
}

output "security_group_ids" {
  description = "Database security groups, by region."
  value = {
    (var.primary_region)   = aws_security_group.primary.id
    (var.secondary_region) = aws_security_group.secondary.id
  }
}

output "alert_topic_arns" {
  description = "SNS topics receiving database alarms, by region. Subscribe on-call routing here."
  value = {
    (var.primary_region)   = aws_sns_topic.primary.arn
    (var.secondary_region) = aws_sns_topic.secondary.arn
  }
}
