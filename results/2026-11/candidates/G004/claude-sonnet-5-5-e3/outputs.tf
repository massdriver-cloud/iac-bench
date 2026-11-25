output "global_cluster_id" {
  description = "Aurora global cluster identifier (use with failover-global-cluster / switchover-global-cluster)."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary-region cluster."
  value       = aws_rds_cluster.primary.arn
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary-region cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "primary_writer_endpoint" {
  description = "Cluster (writer) endpoint in the primary region."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_writer_endpoint" {
  description = "Cluster endpoint in the secondary region. Read-only until that region is promoted."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint in the secondary region."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = 5432
}

output "database_name" {
  description = "Initial database name."
  value       = var.database_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the master credentials (primary region only). For break-glass use; services should use IAM authentication."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "iam_db_connect_resources" {
  description = "Resource ARN patterns for an rds-db:connect IAM policy. Include BOTH so the service role keeps working after a regional failover. Replace the trailing * with a specific database user name."
  value = [
    "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*",
    "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*",
  ]
}

output "primary_security_group_id" {
  description = "Security group on the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group on the secondary cluster."
  value       = aws_security_group.secondary.id
}
