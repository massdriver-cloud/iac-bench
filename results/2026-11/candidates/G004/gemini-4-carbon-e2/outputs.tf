output "global_cluster" {
  description = "Aurora Global Database metadata, including the cross-region global writer endpoint that tracks the active primary cluster across failovers."
  value = {
    identifier      = aws_rds_global_cluster.this.id
    arn             = aws_rds_global_cluster.this.arn
    writer_endpoint = aws_rds_global_cluster.this.endpoint
    engine          = aws_rds_global_cluster.this.engine
    engine_version  = aws_rds_global_cluster.this.engine_version
  }
}

output "database_name" {
  description = "Initial PostgreSQL database name created on the Aurora Global Database."
  value       = local.database_name
}

output "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept TLS-encrypted connections."
  value       = var.port
}

output "primary_cluster" {
  description = "Connection endpoints, resource identifiers, security group, and KMS key for the primary regional Aurora cluster."
  value = {
    region              = var.primary_region
    vpc_id              = data.aws_vpc.primary.id
    cluster_identifier  = aws_rds_cluster.primary.id
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = aws_kms_key.primary.arn
  }
}

output "secondary_cluster" {
  description = "Connection endpoints, resource identifiers, security group, and KMS key for the secondary regional Aurora cluster (warm failover target and write-forwarding reader)."
  value = {
    region              = var.secondary_region
    vpc_id              = data.aws_vpc.secondary.id
    cluster_identifier  = aws_rds_cluster.secondary.id
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = aws_kms_replica_key.secondary.arn
  }
}

output "iam_database_authentication" {
  description = "Customer-managed IAM policy granting EKS service IAM roles rds-db:connect across both primary and secondary Aurora clusters."
  value = {
    policy_arn             = aws_iam_policy.iam_db_connect.arn
    policy_name            = aws_iam_policy.iam_db_connect.name
    allowed_database_users = sort(tolist(local.iam_db_users))
  }
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the KMS-encrypted, RDS-managed master administrative credential (used for initial role provisioning and schema migrations)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}
