output "global_cluster_identifier" {
  description = "Aurora Global Database identifier used during regional failover operations."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary-region Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint of the primary-region Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "Endpoint of the warm secondary-region cluster (available after promotion)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "primary_cluster_resource_id" {
  description = "Immutable RDS cluster resource ID for IAM database authentication policy construction."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "secondary_cluster_resource_id" {
  description = "Immutable RDS cluster resource ID for IAM database authentication policy construction."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "master_user_secret_arn" {
  description = "RDS-managed Secrets Manager secret ARN for the administrator password."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
  sensitive   = true
}
