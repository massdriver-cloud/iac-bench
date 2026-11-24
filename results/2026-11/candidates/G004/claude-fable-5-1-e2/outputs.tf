output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database (use with `aws rds switchover-global-cluster` / `failover-global-cluster`)."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

output "master_username" {
  description = "Break-glass master username."
  value       = var.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret holding the master password (primary region)."
  value       = one(aws_rds_cluster.primary.master_user_secret[*].secret_arn)
}

output "primary" {
  description = "Primary-region cluster details. Services in this region connect to writer_endpoint for writes and reader_endpoint for reads."
  value = {
    region              = var.primary_region
    cluster_id          = aws_rds_cluster.primary.id
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = aws_kms_key.primary.arn
    instance_ids        = aws_rds_cluster_instance.primary[*].id
  }
}

output "secondary" {
  description = "Secondary-region cluster details. Services in this region connect to writer_endpoint (writes are forwarded to the primary until this cluster is promoted) and reader_endpoint for reads."
  value = {
    region              = var.secondary_region
    cluster_id          = aws_rds_cluster.secondary.id
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = aws_kms_key.secondary.arn
    instance_ids        = aws_rds_cluster_instance.secondary[*].id
  }
}

output "iam_connect_policy_arn" {
  description = "Attach this policy to a service's IAM (IRSA) role to let it connect with IAM database authentication in either region."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_database_usernames" {
  description = "PostgreSQL roles covered by iam_connect_policy_arn. Create each with `CREATE ROLE <name> LOGIN; GRANT rds_iam TO <name>;`."
  value       = var.iam_database_usernames
}

output "monitoring_role_arn" {
  description = "IAM role used for Enhanced Monitoring."
  value       = aws_iam_role.monitoring.arn
}
