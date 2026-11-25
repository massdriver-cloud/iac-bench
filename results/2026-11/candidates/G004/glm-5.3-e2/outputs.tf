output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database (used by the failover runbook)."
  value       = aws_rds_global_cluster.this.global_cluster_identifier
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "engine_version" {
  description = "Aurora PostgreSQL engine version in use."
  value       = local.engine_version
}

output "primary_cluster" {
  description = "Primary (writable) cluster: endpoints and identifiers."
  value = {
    region          = var.primary_region
    identifier      = aws_rds_cluster.primary.cluster_identifier
    arn             = aws_rds_cluster.primary.arn
    resource_id     = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint = aws_rds_cluster.primary.endpoint
    reader_endpoint = aws_rds_cluster.primary.reader_endpoint
    port            = aws_rds_cluster.primary.port
    database_name   = aws_rds_cluster.primary.database_name
  }
}

output "secondary_cluster" {
  description = "Secondary (standby, readable) cluster: endpoints and identifiers. The endpoint becomes the writer endpoint after promotion."
  value = {
    region          = var.secondary_region
    identifier      = aws_rds_cluster.secondary.cluster_identifier
    arn             = aws_rds_cluster.secondary.arn
    resource_id     = aws_rds_cluster.secondary.cluster_resource_id
    endpoint        = aws_rds_cluster.secondary.endpoint
    reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
    port            = aws_rds_cluster.secondary.port
  }
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the RDS-managed master credentials (primary region). Break-glass access only - services use IAM auth."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "rds_db_connect_policy_arn" {
  description = "IAM policy to attach to EKS service roles so their pods can mint IAM auth tokens for this database."
  value       = aws_iam_policy.rds_db_connect.arn
}

output "database_subnet_ids" {
  description = "Subnets the clusters were placed in, per region."
  value = {
    primary   = local.primary_subnet_ids
    secondary = local.secondary_subnet_ids
  }
}

output "security_group_ids" {
  description = "Security groups controlling access to the clusters, per region."
  value = {
    primary   = aws_security_group.primary.id
    secondary = aws_security_group.secondary.id
  }
}

output "kms_key_arns" {
  description = "Customer-managed KMS keys protecting the clusters, per region."
  value = {
    primary   = aws_kms_key.primary.arn
    secondary = aws_kms_key.secondary.arn
  }
}
