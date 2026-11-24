output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the initial database in the cluster."
  value       = var.database_name
}

output "port" {
  description = "Port the clusters listen on."
  value       = var.port
}

output "primary" {
  description = "Primary (read/write) region: endpoints, identifiers and security objects."
  value = {
    region                 = var.primary_region
    cluster_identifier     = aws_rds_cluster.primary.cluster_identifier
    cluster_arn            = aws_rds_cluster.primary.arn
    cluster_resource_id    = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint        = aws_rds_cluster.primary.endpoint
    reader_endpoint        = aws_rds_cluster.primary.reader_endpoint
    security_group_id      = aws_security_group.primary.id
    kms_key_arn            = local.primary_kms_key_arn
    master_user_secret_arn = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
    alerts_topic_arn       = aws_sns_topic.alerts_primary.arn
  }
}

output "secondary" {
  description = "Secondary (read-only standby / DR target) region: endpoints, identifiers and security objects."
  value = {
    region              = var.secondary_region
    cluster_identifier  = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    reader_endpoint     = aws_rds_cluster.secondary.endpoint
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = local.secondary_kms_key_arn
    alerts_topic_arn    = aws_sns_topic.alerts_secondary.arn
  }
}

output "iam_db_auth" {
  description = "IAM database authentication is enabled. Allow each service's IAM role to connect by granting rds-db:connect on '<dbuser_arn_prefix>/<db_user_name>' for the region(s) it connects from."
  value = {
    enabled                     = true
    primary_dbuser_arn_prefix   = "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}"
    secondary_dbuser_arn_prefix = "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}"
  }
}

output "enhanced_monitoring_role_arn" {
  description = "IAM role used for RDS enhanced monitoring on all instances."
  value       = aws_iam_role.enhanced_monitoring.arn
}
