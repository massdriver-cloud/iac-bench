output "global_writer_endpoint" {
  description = "Global writer endpoint; reconnect using this name after a managed regional failover."
  value       = aws_rds_global_cluster.this.endpoint
}
