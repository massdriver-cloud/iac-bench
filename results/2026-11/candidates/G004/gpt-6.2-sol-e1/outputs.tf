output "global_cluster_identifier" {
  description = "Identifier for managed Aurora global switchovers and failovers."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "AWS-managed global writer hostname; follows the current writer region after managed switchovers/failovers."
  value       = aws_rds_global_cluster.this.endpoint
}

output "regional_clusters" {
  description = "Member information keyed by region, not by current writer/reader role. Use the target ARN for managed DR operations."
  value = {
    (var.regions.primary) = {
      identifier      = aws_rds_cluster.primary.cluster_identifier
      arn             = aws_rds_cluster.primary.arn
      writer_endpoint = aws_rds_cluster.primary.endpoint
      reader_endpoint = aws_rds_cluster.primary.reader_endpoint
    }
    (var.regions.secondary) = {
      identifier      = aws_rds_cluster.secondary.cluster_identifier
      arn             = aws_rds_cluster.secondary.arn
      writer_endpoint = aws_rds_cluster.secondary.endpoint
      reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
    }
  }
}

output "port" {
  value = local.port
}

output "database_name" {
  value = var.database_name
}

output "application_db_user" {
  value = var.application_db_user
}

output "admin_username" {
  value = local.admin
}

output "admin_secret_arns" {
  description = "Secrets Manager references only; grant GetSecretValue and KMS Decrypt exclusively to approved database administrators or rotation principals."
  value = {
    (var.regions.primary)   = aws_secretsmanager_secret.admin.arn
    (var.regions.secondary) = local.admin_secret_replica_arn
  }
}

output "incident_topic_arns" {
  description = "Subscribe and test a paging integration in both regions before production use."
  value = {
    (var.regions.primary)   = local.primary_topic
    (var.regions.secondary) = local.secondary_topic
  }
}
