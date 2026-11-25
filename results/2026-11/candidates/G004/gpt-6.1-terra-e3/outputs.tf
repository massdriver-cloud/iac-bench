output "global_cluster_id" {
  value = aws_rds_global_cluster.this.id
}
output "primary_writer_endpoint" {
  description = "Initial primary cluster writer endpoint; use the global writer endpoint for regional failover."
  value       = aws_rds_cluster.primary.endpoint
}
output "secondary_reader_endpoint" {
  description = "Initial secondary cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}
output "primary_cluster_arn" {
  value = aws_rds_cluster.primary.arn
}
output "secondary_cluster_arn" {
  value = aws_rds_cluster.secondary.arn
}
output "admin_secret_arn" {
  description = "Administrator secret ARN in the initial primary region; Secrets Manager replicates it to the secondary region."
  value       = aws_secretsmanager_secret.admin.arn
}
output "database_security_group_ids" {
  value = { primary = aws_security_group.primary.id, secondary = aws_security_group.secondary.id }
}
