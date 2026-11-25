# -----------------------------------------------------------------------------
# Global & Cross-Region Connection Outputs
# -----------------------------------------------------------------------------

output "global_cluster_identifier" {
  description = "Identifier of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "global_writer_endpoint" {
  description = "Aurora Global Database writer DNS endpoint that automatically tracks the active writer cluster across switchover and regional failover."
  value       = aws_rds_global_cluster.this.endpoint
}

output "database_name" {
  description = "PostgreSQL database name created in the Aurora cluster."
  value       = local.database_name
}

output "port" {
  description = "TCP port on which Aurora PostgreSQL listens."
  value       = var.port
}

output "engine_version" {
  description = "Resolved Aurora PostgreSQL engine version deployed across both regions."
  value       = local.engine_version
}

# -----------------------------------------------------------------------------
# EKS IAM Authentication & Network Integration Outputs
# -----------------------------------------------------------------------------

output "iam_connect_policy_arn" {
  description = "Managed IAM policy ARN granting rds-db:connect for the service's application DB role(s) against both primary and secondary regional clusters."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_readonly_connect_policy_arn" {
  description = "Managed IAM policy ARN granting rds-db:connect for read-only DB role(s) against both primary and secondary regional clusters."
  value       = aws_iam_policy.db_connect_readonly.arn
}

output "db_iam_users" {
  description = "PostgreSQL role names authorized for read-write IAM token authentication (grant rds_iam to these roles inside PostgreSQL)."
  value       = local.db_iam_users
}

output "db_readonly_iam_users" {
  description = "PostgreSQL role names authorized for read-only IAM token authentication (grant rds_iam to these roles inside PostgreSQL)."
  value       = local.db_readonly_iam_users
}

output "client_security_group_ids" {
  description = "Dedicated client security group IDs per region; attach to EKS pods (Security Groups for Pods) or EKS node groups to allow TCP access to Aurora."
  value = {
    primary   = aws_security_group.client_primary.id
    secondary = aws_security_group.client_secondary.id
  }
}

output "master_user_secret_arn" {
  description = "AWS Secrets Manager ARN containing the RDS-managed, automatically rotated master user credentials (encrypted with the primary KMS key)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

# -----------------------------------------------------------------------------
# Regional Cluster Details (Primary & Secondary)
# -----------------------------------------------------------------------------

output "primary_cluster" {
  description = "Connection, network, security, and alerting metadata for the primary region Aurora cluster."
  value = {
    region                     = var.primary_region
    vpc_id                     = data.aws_vpc.primary.id
    cluster_identifier         = aws_rds_cluster.primary.cluster_identifier
    cluster_arn                = aws_rds_cluster.primary.arn
    cluster_resource_id        = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint            = aws_rds_cluster.primary.endpoint
    reader_endpoint            = aws_rds_cluster.primary.reader_endpoint
    instance_identifiers       = aws_rds_cluster_instance.primary[*].identifier
    database_security_group_id = aws_security_group.db_primary.id
    client_security_group_id   = aws_security_group.client_primary.id
    kms_key_arn                = aws_kms_key.primary.arn
    alert_sns_topic_arn        = aws_sns_topic.primary_alerts.arn
  }
}

output "secondary_cluster" {
  description = "Connection, network, security, and alerting metadata for the warm secondary region Aurora cluster."
  value = {
    region                     = var.secondary_region
    vpc_id                     = data.aws_vpc.secondary.id
    cluster_identifier         = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn                = aws_rds_cluster.secondary.arn
    cluster_resource_id        = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint            = aws_rds_cluster.secondary.endpoint
    reader_endpoint            = aws_rds_cluster.secondary.reader_endpoint
    instance_identifiers       = aws_rds_cluster_instance.secondary[*].identifier
    database_security_group_id = aws_security_group.db_secondary.id
    client_security_group_id   = aws_security_group.client_secondary.id
    kms_key_arn                = aws_kms_key.secondary.arn
    alert_sns_topic_arn        = aws_sns_topic.secondary_alerts.arn
  }
}
