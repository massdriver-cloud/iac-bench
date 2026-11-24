output "global_cluster_identifier" {
  value = aws_rds_global_cluster.database.id
}
output "global_writer_endpoint" {
  description = "AWS-managed global writer DNS name; follows managed switchovers/failovers. Use regional endpoints for the documented IAM authentication integration."
  value       = aws_rds_global_cluster.database.endpoint
}
output "regional_endpoints" {
  description = "Region-local cluster endpoints for TLS/IAM connections. primary/secondary identify deployment locations, not current writer roles."
  value = {
    primary   = { region = var.primary_region, cluster_arn = aws_rds_cluster.primary.arn, writer = aws_rds_cluster.primary.endpoint, reader = aws_rds_cluster.primary.reader_endpoint }
    secondary = { region = var.secondary_region, cluster_arn = aws_rds_cluster.secondary.arn, writer = aws_rds_cluster.secondary.endpoint, reader = aws_rds_cluster.secondary.reader_endpoint }
  }
}
output "administrator_secret_arn" {
  description = "Break-glass credentials; replicated to the recovery region. Secret contents are never output."
  value       = aws_secretsmanager_secret.administrator.arn
}
output "administrator_secret_locations" {
  description = "Secret name is identical in both regions; retrieve by name from the surviving region. Save with the incident runbook."
  value = {
    name     = aws_secretsmanager_secret.administrator.name
    regions  = [var.primary_region, var.secondary_region]
    kms_keys = { primary = aws_kms_key.primary.arn, secondary = aws_kms_key.secondary.arn }
  }
}
output "application_connect_policy_arn" {
  value = aws_iam_policy.application.arn
}
output "security_group_ids" {
  value = { primary = aws_security_group.primary.id, secondary = aws_security_group.secondary.id }
}
output "database_name" { value = var.database_name }
output "application_db_user" { value = var.application_db_user }
