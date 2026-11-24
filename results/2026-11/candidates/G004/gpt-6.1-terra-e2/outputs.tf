output "global_cluster_identifier" {
  value = aws_rds_global_cluster.this.id
}
output "primary_writer_endpoint" {
  value = aws_rds_cluster.primary.endpoint
}
output "primary_reader_endpoint" {
  value = aws_rds_cluster.primary.reader_endpoint
}
output "secondary_writer_endpoint" {
  description = "Cluster endpoint in the DR region; writable only after promotion."
  value       = aws_rds_cluster.secondary.endpoint
}
output "secondary_reader_endpoint" {
  value = aws_rds_cluster.secondary.reader_endpoint
}
output "database_name" {
  value = var.database_name
}
output "primary_cluster_resource_id" {
  description = "Use in IAM rds-db:connect policies."
  value       = aws_rds_cluster.primary.cluster_resource_id
}
output "secondary_cluster_resource_id" {
  description = "Use in IAM rds-db:connect policies for regional failover."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}
output "master_secret_arn" {
  value       = aws_secretsmanager_secret.master.arn
  description = "Bootstrap admin credential; Secrets Manager replicates it to the secondary region."
}
output "primary_security_group_id" {
  value = aws_security_group.primary.id
}
output "secondary_security_group_id" {
  value = aws_security_group.secondary.id
}
