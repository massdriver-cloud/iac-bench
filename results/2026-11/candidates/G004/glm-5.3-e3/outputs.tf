###############################################################################
# Outputs.
#
# Endpoints and identifiers are what a service's Terraform/Kubernetes config
# consumes; the cluster resource IDs are the pieces needed to build the
# rds-db:connect policies that let EKS service accounts authenticate with
# their IAM roles (see README for the wiring). The region outputs make the
# failover runbook copy-pasteable.
###############################################################################

output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database — the handle for failover operations."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "engine_version" {
  description = "The Aurora PostgreSQL version the global database (and therefore both clusters) is pinned to."
  value       = aws_rds_global_cluster.this.engine_version
}

output "primary_region" {
  description = "Region hosting the primary (writable) cluster."
  value       = var.primary_region
}

output "secondary_region" {
  description = "Region hosting the DR (warm-standby) cluster — the failover target."
  value       = var.secondary_region
}

output "primary_cluster_identifier" {
  description = "Identifier of the primary region's cluster."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "ARN of the primary region's cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_writer_endpoint" {
  description = "Writer endpoint of the primary region's cluster — what services use day to day."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint of the primary region's cluster — for scaling reads without touching the writer."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_cluster_resource_id" {
  description = "RDS resource ID (cluster-XXXX) of the primary cluster — used to build rds-db:connect IAM policies."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "secondary_cluster_identifier" {
  description = "Identifier of the DR region's cluster."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "ARN of the DR region's cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_writer_endpoint" {
  description = "Writer endpoint of the DR region's cluster — becomes the write endpoint once the region is promoted."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint of the DR region's cluster — serves local reads in the DR region today."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_cluster_resource_id" {
  description = "RDS resource ID (cluster-XXXX) of the DR cluster — used to build rds-db:connect IAM policies."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the break-glass master credentials (created, stored, and rotated by RDS — never in OpenTofu state)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "primary_security_group_id" {
  description = "Security group controlling access to the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group controlling access to the DR cluster."
  value       = aws_security_group.secondary.id
}

output "primary_db_subnet_group_name" {
  description = "DB subnet group of the primary cluster."
  value       = aws_db_subnet_group.primary.name
}

output "secondary_db_subnet_group_name" {
  description = "DB subnet group of the DR cluster."
  value       = aws_db_subnet_group.secondary.name
}
