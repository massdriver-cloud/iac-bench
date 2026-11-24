output "cluster_resource_ids" {
  description = "Immutable regional DB cluster resource IDs used in rds-db:connect IAM policy ARNs."
  value = {
    primary   = aws_rds_cluster.primary.cluster_resource_id
    secondary = aws_rds_cluster.secondary.cluster_resource_id
  }
}
