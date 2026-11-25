output "global_cluster_identifier" {
  description = "Global cluster ID used by switchover/failover APIs."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "global_writer_endpoint" {
  description = "Aurora-managed global writer DNS name. Applications using this endpoint are directed to the current writer after a managed switchover or failover."
  value       = aws_rds_global_cluster.this.endpoint
}

output "regional_endpoints" {
  description = "Regional cluster and reader endpoints. Prefer global_writer_endpoint for the write workload; use reader endpoints only for explicitly read-only traffic."
  value = {
    primary = {
      region = var.primary_region
      writer = aws_rds_cluster.primary.endpoint
      reader = aws_rds_cluster.primary.reader_endpoint
    }
    secondary = {
      region = var.secondary_region
      writer = aws_rds_cluster.secondary.endpoint
      reader = aws_rds_cluster.secondary.reader_endpoint
    }
  }
}

output "database_port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed administrative secret. The secret value is never exposed through OpenTofu."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "alert_topic_arns" {
  description = "Regional SNS topics for paging integrations. Subscribe the platform on-call destination in both regions."
  value = {
    primary   = aws_sns_topic.primary_alerts.arn
    secondary = aws_sns_topic.secondary_alerts.arn
  }
}

output "regional_cluster_arns" {
  description = "Regional cluster ARNs, including the target required for recovery."
  value = {
    primary   = aws_rds_cluster.primary.arn
    secondary = aws_rds_cluster.secondary.arn
  }
}

output "unplanned_failover_command" {
  description = "Managed cross-region failover command. Confirm regional failure and current RPO before running; this operation can discard writes not yet replicated."
  value       = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.global_cluster_identifier} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}

output "planned_switchover_command" {
  description = "Zero-data-loss managed switchover command for drills and planned region changes. Both regions must be healthy."
  value       = "aws rds switchover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.global_cluster_identifier} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}

output "application_connection_requirements" {
  description = "Connection contract for EKS services."
  value = {
    tls                     = "required (verify-full with the current RDS CA bundle)"
    iam_authentication      = "enabled; grant rds-db:connect to the workload IAM role and create the matching PostgreSQL IAM user"
    administrative_password = "RDS-managed in Secrets Manager; do not use the master user for application connections"
    recommended_dns         = "global_writer_endpoint"
  }
}
