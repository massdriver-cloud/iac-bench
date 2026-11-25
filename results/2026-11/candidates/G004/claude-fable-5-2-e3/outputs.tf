output "writer_endpoint" {
  description = "Global writer endpoint. Point services here: it always resolves to the writer in whichever region is currently primary, so a failover needs no application config change."
  value       = aws_rds_global_cluster.this.endpoint
}

output "reader_endpoints" {
  description = "Read-only endpoint in each region, for read traffic that should stay in-region."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.reader_endpoint
    (var.secondary_region) = aws_rds_cluster.secondary.reader_endpoint
  }
}

output "cluster_endpoints" {
  description = "Regional cluster endpoint in each region. Only the endpoint in the current writer region accepts writes."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.endpoint
    (var.secondary_region) = aws_rds_cluster.secondary.endpoint
  }
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

output "global_cluster_identifier" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "cluster_arns" {
  description = "ARN of the regional cluster in each region."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.arn
    (var.secondary_region) = aws_rds_cluster.secondary.arn
  }
}

output "cluster_resource_ids" {
  description = "Cluster resource ID in each region (used in rds-db:connect IAM policies)."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.cluster_resource_id
    (var.secondary_region) = aws_rds_cluster.secondary.cluster_resource_id
  }
}

output "security_group_ids" {
  description = "Security group attached to the database in each region."
  value = {
    (var.primary_region)   = aws_security_group.primary.id
    (var.secondary_region) = aws_security_group.secondary.id
  }
}

output "connect_policy_arn" {
  description = "IAM policy that lets a role log in as the application database users with IAM authentication. Attach it to service roles (or list them in app_role_names)."
  value       = one(aws_iam_policy.connect[*].arn)
}

output "master_secret_arn" {
  description = "Secrets Manager secret holding the break-glass master credentials (replicated to the secondary region under the same name)."
  value       = aws_secretsmanager_secret.master.arn
}

output "kms_key_arns" {
  description = "Customer-managed KMS key protecting the database in each region."
  value = {
    (var.primary_region)   = aws_kms_key.primary.arn
    (var.secondary_region) = aws_kms_key.secondary.arn
  }
}

output "regional_failover_commands" {
  description = "Run the command for the SURVIVING region to promote it when the current writer region is down. --allow-data-loss accepts the loss of writes not yet replicated (normally under a second)."
  value = {
    (var.primary_region)   = "aws rds failover-global-cluster --region ${var.primary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.primary.arn} --allow-data-loss"
    (var.secondary_region) = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
  }
}
