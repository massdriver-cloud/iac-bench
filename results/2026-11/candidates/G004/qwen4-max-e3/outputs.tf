output "global_cluster_identifier" {
  description = "Identifier of the Aurora Global Database."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "primary_cluster_identifier" {
  description = "Cluster identifier in the primary region."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "secondary_cluster_identifier" {
  description = "Cluster identifier in the DR region."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "primary_endpoint" {
  description = "Writer endpoint (primary region). Use for reads+writes."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint (primary region). Use for read-only traffic."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint in the DR region. Serves stale-by-~1s reads today; becomes the writer endpoint target after a regional failover."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.primary.port
}

output "database_name" {
  description = "Initial database name."
  value       = var.database_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-managed break-glass admin credentials. Applications must NOT use this; use IAM auth."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "db_connect_policy_arn" {
  description = "Attach this IAM policy to the service's EKS pod role (IRSA) to allow IAM database authentication as var.app_db_username in both regions."
  value       = aws_iam_policy.db_connect.arn
}

output "app_db_username" {
  description = "PostgreSQL user the application should connect as (must be created with GRANT rds_iam)."
  value       = var.app_db_username
}

output "primary_region" {
  description = "Primary AWS region."
  value       = var.primary_region
}

output "secondary_region" {
  description = "DR AWS region."
  value       = var.secondary_region
}

output "security_group_ids" {
  description = "Cluster security group IDs by region."
  value = {
    (var.primary_region)   = aws_security_group.primary.id
    (var.secondary_region) = aws_security_group.secondary.id
  }
}

output "failover_runbook" {
  description = "Quick reference for regional failover (see README.md for the full runbook)."
  value       = <<-EOT
    Planned switchover (no data loss, zero downtime target):
      aws rds switchover-global-cluster --global-cluster-identifier ${local.global_cluster_id} \
        --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.primary_region}
    Unplanned regional outage (RPO ~1s, RTO < 1 min with warm readers):
      aws rds remove-from-global-cluster --global-cluster-identifier ${local.global_cluster_id} \
        --db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.secondary_region}
      aws rds failover-db-cluster --db-cluster-identifier ${local.secondary_cluster_id} --region ${var.secondary_region}
    Then point the service's DB endpoint configuration at ${aws_rds_cluster.secondary.endpoint}.
  EOT
}
