output "global_cluster_identifier" {
  description = "Aurora Global Database identifier (used for switchover/failover)."
  value       = aws_rds_global_cluster.this.id
}

output "primary_writer_endpoint" {
  description = "Writer endpoint in the primary region."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint in the secondary region (becomes writable after failover)."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "Cluster endpoint in the secondary region (writer after failover)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "port" {
  value = 5432
}

output "database_name" {
  value = local.database_name
}

output "primary_cluster_resource_id" {
  description = "Primary cluster resource ID, for building rds-db:connect IAM policies for EKS service roles."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "secondary_cluster_resource_id" {
  description = "Secondary cluster resource ID, for building rds-db:connect IAM policies for EKS service roles."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "iam_connect_resource_arn_prefixes" {
  description = "rds-db:connect ARN prefixes (append the DB user name) covering both regions."
  value = [
    "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/",
    "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/",
  ]
}

output "master_secret_arn" {
  description = "Secrets Manager ARN holding master credentials (replicated to the secondary region)."
  value       = aws_secretsmanager_secret.master.arn
}

output "security_group_ids" {
  value = {
    primary   = aws_security_group.primary.id
    secondary = aws_security_group.secondary.id
  }
}

output "kms_key_arns" {
  value = {
    primary   = aws_kms_key.primary.arn
    secondary = aws_kms_key.secondary.arn
  }
}
