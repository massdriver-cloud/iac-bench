output "primary_cluster_id" {
  description = "The ID of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_endpoint" {
  description = "The cluster endpoint for the primary region"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "The reader endpoint for the primary region"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "The ID of the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_endpoint" {
  description = "The cluster endpoint for the secondary region"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "The reader endpoint for the secondary region"
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "Name of the default database created"
  value       = var.db_name
}

output "master_username" {
  description = "The master username"
  value       = aws_rds_cluster.primary.master_username
}

output "master_password" {
  description = "The generated master password"
  value       = random_password.master_password.result
  sensitive   = true
}
