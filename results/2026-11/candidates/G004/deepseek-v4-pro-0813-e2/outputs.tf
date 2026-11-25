output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database. Use this for failover and global-cluster operations."
  value       = aws_rds_global_cluster.this.id
}

output "database_name" {
  description = "Initial database name."
  value       = var.database_name
}

output "port" {
  description = "PostgreSQL port."
  value       = var.port
}

output "primary_cluster_identifier" {
  description = "Primary Aurora cluster identifier."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_writer_endpoint" {
  description = "Primary cluster writer endpoint."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary cluster reader endpoint."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_identifier" {
  description = "Secondary Aurora cluster identifier."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_writer_endpoint" {
  description = "Secondary cluster endpoint. This becomes writable after promotion."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "master_secret_arn" {
  description = "Secrets Manager secret ARN containing the generated master database credentials."
  value       = aws_secretsmanager_secret.master.arn
}

output "primary_security_group_id" {
  description = "Security group protecting the primary cluster. Add its ID to the EKS services that need access if not using the VPC CIDR rule."
  value       = one(aws_security_group.primary[*].id)
}

output "secondary_security_group_id" {
  description = "Security group protecting the secondary cluster."
  value       = one(aws_security_group.secondary[*].id)
}

output "failover_notes" {
  description = "Operational notes for RPO/RTO. The database is a global database; failover is performed with the AWS API, CLI, or console."
  value = {
    rpo      = "Typically < 1 second; check CurrentLag on the global cluster."
    rto      = "Typically ~1 minute for managed cross-region failover plus application DNS cutover."
    cli_hint = "aws rds failover-db-cluster --db-cluster-identifier ${aws_rds_cluster.secondary.cluster_identifier}"
  }
}