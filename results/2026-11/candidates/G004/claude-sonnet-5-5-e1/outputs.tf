output "global_cluster_id" {
  description = "Aurora global cluster identifier."
  value       = aws_rds_global_cluster.this.id
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "primary" {
  description = "Primary region cluster endpoints."
  value = {
    region          = var.primary_region
    cluster_arn     = aws_rds_cluster.primary.arn
    endpoint        = aws_rds_cluster.primary.endpoint
    reader_endpoint = aws_rds_cluster.primary.reader_endpoint
  }
}

output "secondary" {
  description = "Secondary region cluster endpoints. Read-only until promoted; applications should reach the writer via a DNS name they can repoint on failover."
  value = {
    region          = var.secondary_region
    cluster_arn     = aws_rds_cluster.secondary.arn
    endpoint        = aws_rds_cluster.secondary.endpoint
    reader_endpoint = aws_rds_cluster.secondary.reader_endpoint
  }
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the administrator credential (administrators only; applications use IAM authentication)."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "cluster_resource_ids" {
  description = "Cluster resource IDs per region, for building rds-db:connect IAM policies (arn:aws:rds-db:<region>:<account>:dbuser:<id>/<db user>)."
  value = {
    primary   = aws_rds_cluster.primary.cluster_resource_id
    secondary = aws_rds_cluster.secondary.cluster_resource_id
  }
}

output "security_group_ids" {
  description = "Database security group IDs per region."
  value = {
    primary   = aws_security_group.primary.id
    secondary = aws_security_group.secondary.id
  }
}

output "kms_key_arns" {
  description = "KMS key ARNs per region."
  value = {
    primary   = aws_kms_key.primary.arn
    secondary = aws_kms_key.secondary.arn
  }
}
