output "global_cluster_identifier" {
  description = "Identifier for RDS managed switchovers and failovers."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "AWS-managed DNS name tracking the global writer. IAM clients should use the matching regional endpoint and token signing region."
  value       = aws_rds_global_cluster.this.endpoint
}

output "regional_clusters" {
  description = "Connection and operations information keyed by AWS region. Cluster endpoint is writable only in the current writer region."
  value = {
    (var.primary_region) = {
      arn                = aws_rds_cluster.primary.arn
      cluster_identifier = aws_rds_cluster.primary.cluster_identifier
      cluster_endpoint   = aws_rds_cluster.primary.endpoint
      reader_endpoint    = aws_rds_cluster.primary.reader_endpoint
      security_group_id  = aws_security_group.primary.id
    }
    (var.secondary_region) = {
      arn                = aws_rds_cluster.secondary.arn
      cluster_identifier = aws_rds_cluster.secondary.cluster_identifier
      cluster_endpoint   = aws_rds_cluster.secondary.endpoint
      reader_endpoint    = aws_rds_cluster.secondary.reader_endpoint
      security_group_id  = aws_security_group.secondary.id
    }
  }
}

output "database_name" {
  description = "Initial service database."
  value       = local.database_name
}

output "port" {
  description = "PostgreSQL TCP port."
  value       = local.port
}

output "runtime_db_username" {
  description = "IAM database login to bootstrap on the writer."
  value       = local.app_user
}

output "runtime_iam_policy_arn" {
  description = "Attach to the service's workload IAM roles unless app_iam_role_names already manages those attachments."
  value       = aws_iam_policy.runtime.arn
}

output "admin_secret_arn" {
  description = "Primary Secrets Manager ARN. The same secret name is replicated to the recovery region."
  value       = aws_secretsmanager_secret.admin.arn
}

output "admin_secret_name" {
  description = "Regional secret name for authorized database operators."
  value       = aws_secretsmanager_secret.admin.name
}

output "alarm_topic_arns" {
  description = "Alarm topics by AWS region."
  value       = { for key, region in local.key_regions : region => aws_sns_topic.alarms[key].arn }
}
