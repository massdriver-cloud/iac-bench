output "global_cluster_identifier" {
  description = "Global cluster identifier used by switchover and failover commands."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_identifier" {
  description = "Identifier of the primary regional cluster."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary regional cluster."
  value       = aws_rds_cluster.primary.arn
}

output "secondary_cluster_identifier" {
  description = "Identifier of the secondary regional cluster; the managed failover target."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary regional cluster; the managed failover target."
  value       = aws_rds_cluster.secondary.arn
}

output "primary_writer_endpoint" {
  description = "Writer endpoint of the cluster initially deployed as primary. Its runtime role can change after a managed role transition."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Private DNS endpoint for primary-cluster reads."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_writer_endpoint_after_promotion" {
  description = "Secondary cluster endpoint for applications in the recovery Region after managed switchover/failover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Private DNS endpoint for secondary-cluster reads before or after promotion."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_port" {
  description = "PostgreSQL listener port."
  value       = var.database_port
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = var.database_name
}

output "primary_security_group_id" {
  description = "Database security-group ID in the primary Region."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Database security-group ID in the secondary Region."
  value       = aws_security_group.secondary.id
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed primary master-user secret. The password is not exposed through OpenTofu outputs."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "iam_connect_policy_arn" {
  description = "Policy permitting rds-db:connect to every configured IAM database user on both regional clusters. Null when iam_database_users is empty."
  value       = local.create_iam_policy ? aws_iam_policy.iam_database_connect[0].arn : null
}

output "iam_database_users" {
  description = "PostgreSQL users configured for IAM access. They still need CREATE USER and GRANT rds_iam in PostgreSQL."
  value       = local.iam_database_users
}

output "regional_recovery_command" {
  description = "Managed, unplanned regional failover command for the initial topology, sent to the healthy secondary Region. This can lose writes not yet replicated."
  value       = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
}

output "planned_switchover_command" {
  description = "Managed, no-data-loss switchover command for the initial topology, testing, and planned Regional recovery."
  value       = "aws rds switchover-global-cluster --region ${var.primary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}
