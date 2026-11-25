output "global_cluster_id" {
  description = "Identifier of the Aurora global cluster. Use it with `aws rds switchover-global-cluster` (planned) or `aws rds failover-global-cluster` (regional outage)."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "primary" {
  description = "Primary (writer) regional cluster."
  value = {
    region              = var.primary_region
    cluster_identifier  = aws_rds_cluster.primary.cluster_identifier
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    port                = aws_rds_cluster.primary.port
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = aws_kms_key.primary.arn
  }
}

output "secondary" {
  description = "Secondary (disaster-recovery) regional cluster. Its reader endpoint becomes the writer endpoint after promotion."
  value = {
    region              = var.secondary_region
    cluster_identifier  = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    port                = aws_rds_cluster.secondary.port
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = aws_kms_key.secondary.arn
  }
}

output "database_name" {
  description = "Name of the initial database."
  value       = aws_rds_cluster.primary.database_name
}

output "master_username" {
  description = "Master username (break-glass only; applications use IAM authentication)."
  value       = aws_rds_cluster.primary.master_username
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-managed master password (primary region)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "db_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for iam_database_users on both clusters. Attach to the service's EKS pod role."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_database_users" {
  description = "PostgreSQL roles the connect policy covers. Create each with: CREATE ROLE <name> LOGIN; GRANT rds_iam TO <name>;"
  value       = var.iam_database_users
}

output "cluster_parameter_group_names" {
  description = "Cluster parameter group names per region."
  value = {
    primary   = aws_rds_cluster_parameter_group.primary.name
    secondary = aws_rds_cluster_parameter_group.secondary.name
  }
}
