output "global_cluster_identifier" {
  description = "Aurora Global Database identifier shared across both regions."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint in the primary region before a regional failover."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "Cluster endpoint in the secondary region; use after promoting the secondary during regional failover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN for the RDS-generated administrative password. Does not expose the secret value."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "iam_database_username" {
  description = "Database login name to provision with the PostgreSQL rds_iam role and application grants."
  value       = var.iam_database_username
}

output "primary_security_group_id" {
  description = "Security group attached to primary Aurora instances."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group attached to secondary Aurora instances."
  value       = aws_security_group.secondary.id
}
