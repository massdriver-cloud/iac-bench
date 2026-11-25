output "global_cluster_id" {
  value = aws_rds_global_cluster.this.id
}
output "regional_connections" {
  description = "Use cluster (not instance or reader) endpoints for writes. Secondary is read-only until promotion. Resolve/reconnect after failover, with TLS verify-full."
  value = {
    primary = {
      region          = var.primary_region
      cluster_arn     = aws_rds_cluster.primary.arn
      writer_endpoint = aws_rds_cluster.primary.endpoint
      reader_endpoint = aws_rds_cluster.primary.reader_endpoint
      security_group  = aws_security_group.primary.id
    }
    secondary = {
      region          = var.secondary_region
      cluster_arn     = aws_rds_cluster.secondary.arn
      writer_endpoint = aws_rds_cluster.secondary.endpoint
      reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
      security_group  = aws_security_group.secondary.id
    }
  }
}
output "port" { value = 5432 }
output "database_name" { value = var.database_name }
output "admin_secret_arn" {
  description = "Bootstrap/break-glass only. Password is never an output. The secret is replicated into the secondary region; its host field describes the initial writer only."
  value       = aws_secretsmanager_secret.admin.arn
}
output "application_iam_policy_json" {
  description = "Attach this policy to the application's IRSA or EKS Pod Identity role. It grants IAM login to exactly one SQL user on both clusters, including after failover."
  value = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["rds-db:connect"]
      Resource = [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.application_db_user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.application_db_user}"
      ]
    }]
  })
}
output "failover_command" {
  description = "Run from a surviving region after incident authorization. May lose unreplicated writes. Reconcile IaC after promotion before another apply."
  value       = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
}
