output "global_cluster_identifier" {
  description = "Aurora Global Database identifier. The application must use the regional writer endpoint appropriate to its active region."
  value       = aws_rds_global_cluster.this.id
}

output "primary_writer_endpoint" {
  description = "Primary regional cluster writer endpoint."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary regional cluster reader endpoint."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_writer_endpoint" {
  description = "Secondary regional cluster endpoint; writable after global database failover/promotion."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary regional cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "master_secret_arn" {
  description = "Secrets Manager secret ARN for the generated master password. Use only for administrative/bootstrap operations."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
  sensitive   = true
}

output "primary_security_group_id" {
  description = "Primary database security group ID."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Secondary database security group ID."
  value       = aws_security_group.secondary.id
}
