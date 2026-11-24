output "global_cluster_identifier" {
  description = "Aurora global cluster identifier (use for managed switchover/failover)."
  value       = aws_rds_global_cluster.this.id
}

output "global_writer_endpoint" {
  description = "Global writer endpoint. Always resolves to the current writer, in whichever region it lives after a switchover/failover. Applications should connect here."
  value       = aws_rds_global_cluster.this.endpoint
}

output "primary" {
  description = "Primary-region cluster details."
  value = {
    region            = module.primary.region
    cluster_arn       = module.primary.cluster_arn
    writer_endpoint   = module.primary.writer_endpoint
    reader_endpoint   = module.primary.reader_endpoint
    security_group_id = module.primary.security_group_id
  }
}

output "secondary" {
  description = "Secondary-region cluster details (read-only until failover)."
  value = {
    region            = module.secondary.region
    cluster_arn       = module.secondary.cluster_arn
    writer_endpoint   = module.secondary.writer_endpoint
    reader_endpoint   = module.secondary.reader_endpoint
    security_group_id = module.secondary.security_group_id
  }
}

output "database_name" {
  value = local.database_name
}

output "master_secret_arn" {
  description = "Secrets Manager secret (replicated to the secondary region) holding the break-glass master credentials."
  value       = aws_secretsmanager_secret.master.arn
}

output "iam_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for iam_db_users on both clusters; attach to service roles."
  value       = try(aws_iam_policy.connect[0].arn, null)
}
