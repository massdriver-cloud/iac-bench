output "global_cluster_identifier" {
  description = "Identifier of the Aurora global cluster; the target of the failover runbook."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_identifier" {
  description = "Identifier of the read-write cluster during normal operation."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_writer_endpoint" {
  description = "Read-write endpoint during normal operation."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Load-balanced reader endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_identifier" {
  description = "Identifier of the warm standby cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary cluster; pass this as the failover target."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_writer_endpoint" {
  description = "Becomes the read-write endpoint once a regional failover promotes the secondary cluster."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Serves local reads in the secondary region even before any failover."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

output "master_username" {
  description = "Master username; the password lives in the credentials secrets."
  value       = aws_rds_cluster.primary.master_username
}

output "port" {
  description = "PostgreSQL port."
  value       = local.engine_port
}

output "primary_credentials_secret_arn" {
  description = "Secrets Manager secret with connection details, primary region."
  value       = aws_secretsmanager_secret.primary.arn
}

output "secondary_credentials_secret_arn" {
  description = "Secrets Manager secret with connection details, secondary region (identical name to the primary one)."
  value       = aws_secretsmanager_secret.secondary.arn
}

output "primary_security_group_id" {
  description = "Security group guarding the primary cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group guarding the secondary cluster."
  value       = aws_security_group.secondary.id
}

output "failover_command" {
  description = "The managed-failover CLI command to promote the secondary cluster during a regional outage (see the README runbook)."
  value       = "aws rds failover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}
