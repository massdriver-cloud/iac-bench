output "writer_endpoint" {
  description = "Global writer endpoint: follows the primary through a failover or switchover."
  value       = aws_rds_global_cluster.this.endpoint
}

output "reader_endpoints" {
  description = "Reader endpoint in each region, for read traffic served locally."
  value = {
    primary   = aws_rds_cluster.primary.reader_endpoint
    secondary = aws_rds_cluster.secondary.reader_endpoint
  }
}

output "global_cluster_id" {
  description = "Global cluster identifier, for managed failover and switchover."
  value       = aws_rds_global_cluster.this.id
}

output "cluster_resource_ids" {
  description = "Cluster resource IDs per region, for rds-db:connect IAM policies."
  value = {
    primary   = aws_rds_cluster.primary.cluster_resource_id
    secondary = aws_rds_cluster.secondary.cluster_resource_id
  }
}
