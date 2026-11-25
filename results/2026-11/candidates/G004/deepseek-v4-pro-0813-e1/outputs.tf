output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_identifier" {
  description = "Identifier of the primary regional Aurora cluster."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_endpoint" {
  description = "Primary cluster writer endpoint."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary cluster reader endpoint."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_port" {
  description = "PostgreSQL port used by the primary cluster."
  value       = aws_rds_cluster.primary.port
}

output "secondary_cluster_identifier" {
  description = "Identifier of the secondary regional Aurora cluster."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_endpoint" {
  description = "Secondary cluster endpoint (readers in the secondary region; becomes writer after global failover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_port" {
  description = "PostgreSQL port used by the secondary cluster."
  value       = aws_rds_cluster.secondary.port
}

output "database_name" {
  description = "Name of the application database."
  value       = var.database_name
}

output "master_username" {
  description = "Master database username for break-glass administrative access."
  value       = aws_rds_cluster.primary.master_username
}

output "primary_security_group_id" {
  description = "Security group attached to the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group attached to the secondary cluster."
  value       = aws_security_group.secondary.id
}