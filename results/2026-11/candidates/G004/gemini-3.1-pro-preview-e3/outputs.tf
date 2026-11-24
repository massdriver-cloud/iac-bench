output "global_cluster_id" {
  description = "The ID of the Global Cluster"
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_endpoint" {
  description = "The cluster endpoint of the primary region"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "The reader endpoint of the primary region"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "The cluster endpoint of the secondary region"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "The reader endpoint of the secondary region"
  value       = aws_rds_cluster.secondary.reader_endpoint
}
