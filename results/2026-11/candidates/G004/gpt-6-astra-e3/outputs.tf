output "global_cluster_identifier" { value = aws_rds_global_cluster.this.id }
output "global_writer_endpoint" {
  description = "AWS global writer DNS name. For IAM clients use the active regional cluster endpoint and signing region from regional_clusters; see recovery runbook."
  value       = aws_rds_global_cluster.this.endpoint
}
output "regional_clusters" {
  description = "Primary/secondary are initial placement labels, NOT live writer roles after failover. Discover the live writer with DescribeGlobalClusters."
  value = {
    primary   = { region = var.primary_region, arn = aws_rds_cluster.primary.arn, endpoint = aws_rds_cluster.primary.endpoint, reader_endpoint = aws_rds_cluster.primary.reader_endpoint, security_group_id = aws_security_group.primary.id }
    secondary = { region = var.secondary_region, arn = aws_rds_cluster.secondary.arn, endpoint = aws_rds_cluster.secondary.endpoint, reader_endpoint = aws_rds_cluster.secondary.reader_endpoint, security_group_id = aws_security_group.secondary.id }
  }
}
output "bootstrap_secret_arn" {
  description = "Only grant access to bootstrap/break-glass operators; secret is replicated to the DR region. No password is output."
  value       = aws_secretsmanager_secret.admin.arn
}
output "application_connect_policy_arn" { value = aws_iam_policy.connect.arn }
output "database_name" { value = var.database_name }
output "application_database_user" { value = var.application_database_user }
output "alarm_topic_arns" { value = [aws_sns_topic.primary.arn, aws_sns_topic.secondary.arn] }
