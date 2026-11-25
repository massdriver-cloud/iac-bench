output "global_cluster_identifier" {
  description = "Global database identifier used by the RDS switchover and failover APIs."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "AWS-managed global writer DNS name. See the README for IAM token and TLS hostname handling."
  value       = aws_rds_global_cluster.this.endpoint
}

output "database_name" {
  value = local.database_name
}

output "application_database_user" {
  description = "Create this PostgreSQL login and grant rds_iam plus scoped SQL privileges before serving traffic."
  value       = local.app_db_user
}

output "port" {
  value = local.port
}

output "workload_connect_policy_arn" {
  description = "Attach to the application's EKS workload role if not attached by this module."
  value       = aws_iam_policy.connect.arn
}

output "bootstrap_admin_secret_arn" {
  description = "Secrets Manager primary secret ARN (not its value); the same secret name is replicated to the standby region."
  value       = aws_secretsmanager_secret.admin.arn
}

output "bootstrap_admin_secret_name" {
  value = aws_secretsmanager_secret.admin.name
}

output "regional_clusters" {
  description = "Regional member details. These keys denote creation roles, not the current writer."
  value = {
    (var.primary_region) = {
      arn               = aws_rds_cluster.primary.arn
      identifier        = aws_rds_cluster.primary.id
      resource_id       = aws_rds_cluster.primary.cluster_resource_id
      cluster_endpoint  = aws_rds_cluster.primary.endpoint
      reader_endpoint   = aws_rds_cluster.primary.reader_endpoint
      security_group_id = aws_security_group.primary.id
    }
    (var.secondary_region) = {
      arn               = aws_rds_cluster.secondary.arn
      identifier        = aws_rds_cluster.secondary.id
      resource_id       = aws_rds_cluster.secondary.cluster_resource_id
      cluster_endpoint  = aws_rds_cluster.secondary.endpoint
      reader_endpoint   = aws_rds_cluster.secondary.reader_endpoint
      security_group_id = aws_security_group.secondary.id
    }
  }
}
