output "global_cluster_id" {
  value = aws_rds_global_cluster.this.id
}
output "global_writer_endpoint" {
  description = "AWS global writer endpoint follows managed failover. IAM clients should discover the current writer's regional cluster endpoint and sign tokens for that region (see README)."
  value       = aws_rds_global_cluster.this.endpoint
}
output "regional_endpoints" {
  description = "Physical regional endpoints (labels do not change after promotion). Only the current writer accepts writes."
  value = {
    primary = {
      writer = aws_rds_cluster.primary.endpoint
      reader = aws_rds_cluster.primary.reader_endpoint
      arn    = aws_rds_cluster.primary.arn
    }
    secondary = {
      writer = aws_rds_cluster.secondary.endpoint
      reader = aws_rds_cluster.secondary.reader_endpoint
      arn    = aws_rds_cluster.secondary.arn
    }
  }
}
output "admin_secret_arn" {
  description = "Break-glass admin secret (replicated to the secondary region). No application grants to this secret are created."
  value       = aws_secretsmanager_secret.admin.arn
}
output "database_name" {
  value = "app"
}
output "port" {
  value = 5432
}
output "alert_topic_arns" {
  value = { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn }
}
