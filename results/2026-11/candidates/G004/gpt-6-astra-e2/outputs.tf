output "global_cluster_id" { value = aws_rds_global_cluster.this.id }
output "regional_clusters" {
  description = "Names describe initial roles, not the current writer after a failover. Connect with these native endpoints and verify-full TLS; never instance endpoints."
  value = {
    primary = {
      region          = var.primary_region
      arn             = aws_rds_cluster.primary.arn
      writer_endpoint = aws_rds_cluster.primary.endpoint
      reader_endpoint = aws_rds_cluster.primary.reader_endpoint
      resource_id     = aws_rds_cluster.primary.cluster_resource_id
      security_group  = aws_security_group.primary.id
    }
    secondary = {
      region          = var.secondary_region
      arn             = aws_rds_cluster.secondary.arn
      writer_endpoint = aws_rds_cluster.secondary.endpoint
      reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
      resource_id     = aws_rds_cluster.secondary.cluster_resource_id
      security_group  = aws_security_group.secondary.id
    }
  }
}
output "connection" {
  value = {
    database = var.database_name
    username = var.database_user
    port     = 5432
    sslmode  = "verify-full"
  }
}
output "bootstrap_secret_arn" {
  description = "Privileged bootstrap secret. Replica has same secret name in secondary region. Workload roles are deliberately NOT granted access."
  value       = aws_secretsmanager_secret.admin.arn
}
output "bootstrap_secret_name" { value = aws_secretsmanager_secret.admin.name }
output "iam_connect_policy_arn" { value = aws_iam_policy.connect.arn }
output "alert_topic_arns" {
  value = { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn }
}
