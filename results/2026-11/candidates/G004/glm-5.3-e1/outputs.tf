output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database spanning both regions."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "engine_version" {
  description = "Resolved Aurora PostgreSQL engine version used by every cluster in the global database."
  value       = local.engine_version
}

output "database_name" {
  description = "Name of the initial database inside the cluster."
  value       = local.database_name
}

output "port" {
  description = "Port the clusters listen on."
  value       = var.port
}

output "master_username" {
  description = "Master database user name. Its password is stored in Secrets Manager (see master_secret_arns) and never rendered in outputs."
  value       = var.master_username
}

output "primary_cluster" {
  description = "Primary (writable) regional cluster. Services use writer_endpoint for writes and reader_endpoint for reads in this region."
  value = {
    region              = var.primary_region
    cluster_identifier  = aws_rds_cluster.primary.cluster_identifier
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
  }
}

output "secondary_cluster" {
  description = "Warm-standby regional cluster. Its endpoints serve reads in that region today; after a regional failover, cluster_endpoint serves writes."
  value = {
    region              = var.secondary_region
    cluster_identifier  = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    cluster_endpoint    = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
  }
}

output "master_secret_arns" {
  description = "Secrets Manager ARNs holding the master credentials, replicated by the module to both regions. Read the one in the region you are running in."
  value = {
    (var.primary_region)   = aws_secretsmanager_secret.master_primary.arn
    (var.secondary_region) = aws_secretsmanager_secret.master_secondary.arn
  }
}

output "rds_db_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for iam_db_users on both regional clusters. Attach it to your EKS service account IAM roles. Null when iam_db_users is empty."
  value       = try(aws_iam_policy.rds_db_connect[0].arn, null)
}

output "security_group_ids" {
  description = "Security group controlling PostgreSQL ingress, per region."
  value = {
    (var.primary_region)   = aws_security_group.primary.id
    (var.secondary_region) = aws_security_group.secondary.id
  }
}
