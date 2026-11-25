output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

output "port" {
  description = "Port the clusters listen on."
  value       = var.port
}

output "primary_region" {
  description = "Region hosting the writer cluster."
  value       = var.primary_region
}

output "secondary_region" {
  description = "Region hosting the standby cluster."
  value       = var.secondary_region
}

output "primary_cluster_id" {
  description = "Identifier of the primary (writer) cluster."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary (writer) cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary cluster — point applications here."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint of the primary cluster (load-balanced read replicas)."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "Identifier of the secondary (standby) cluster."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary (standby) cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Endpoint of the secondary cluster (read-only until promoted)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint of the secondary cluster — usable for cross-region read traffic today."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "master_username" {
  description = "Master username (break-glass account)."
  value       = var.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the RDS-managed Secrets Manager secret holding the master password. Null when an explicit master_password was supplied."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "primary_security_group_id" {
  description = "Security group protecting the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group protecting the secondary cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "CMK encrypting the primary cluster's storage, Performance Insights and master secret."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "CMK encrypting the secondary cluster's storage and Performance Insights."
  value       = aws_kms_key.secondary.arn
}

output "primary_db_subnet_group_name" {
  description = "DB subnet group used by the primary cluster."
  value       = aws_db_subnet_group.primary.name
}

output "secondary_db_subnet_group_name" {
  description = "DB subnet group used by the secondary cluster."
  value       = aws_db_subnet_group.secondary.name
}

output "switchover_command" {
  description = "Planned regional recovery (zero data loss, ~1 minute): promotes the secondary cluster to writer."
  value       = "aws rds switchover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.global_cluster_identifier} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.secondary_region}"
}

output "failover_command" {
  description = "Unplanned regional recovery (may lose the last seconds of unreplicated writes): forces the secondary cluster to writer when the primary region is down."
  value       = "aws rds failover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.global_cluster_identifier} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss --region ${var.secondary_region}"
}
