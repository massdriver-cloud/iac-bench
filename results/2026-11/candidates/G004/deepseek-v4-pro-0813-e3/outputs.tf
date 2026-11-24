output "global_cluster_id" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_id" {
  description = "Identifier of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint of the primary Aurora cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "Identifier of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Endpoint of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint of the secondary Aurora cluster."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "Provisioned PostgreSQL database name."
  value       = var.database_name
}

output "master_username" {
  description = "Master database username."
  value       = var.master_username
}

output "master_secret_arn" {
  description = "ARN of the Secrets Manager secret that stores master credentials."
  value       = aws_secretsmanager_secret.master.arn
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary cluster."
  value       = aws_security_group.secondary.id
}

output "failover_command" {
  description = "AWS CLI command to fail the global database over to the secondary cluster."
  value       = "aws rds failover-db-cluster --db-cluster-identifier ${aws_rds_cluster.secondary.id} --region ${var.secondary_region}"
}