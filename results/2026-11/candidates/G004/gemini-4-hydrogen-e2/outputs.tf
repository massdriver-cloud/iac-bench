output "global_cluster_id" {
  description = "Aurora Global Database cluster identifier."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "Aurora Global Database cluster ARN."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Initial PostgreSQL database name."
  value       = local.database_name
}

output "port" {
  description = "PostgreSQL TCP port."
  value       = aws_rds_cluster.primary.port
}

output "primary_cluster_id" {
  description = "Primary regional Aurora PostgreSQL cluster identifier."
  value       = aws_rds_cluster.primary.cluster_identifier
}

output "primary_cluster_arn" {
  description = "Primary regional Aurora PostgreSQL cluster ARN."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_resource_id" {
  description = "Primary regional Aurora PostgreSQL DbiResourceId used for IAM authentication."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_writer_endpoint" {
  description = "Primary cluster writer endpoint."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Primary cluster reader endpoint."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the break-glass master user credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "secondary_cluster_id" {
  description = "Secondary regional Aurora PostgreSQL cluster identifier."
  value       = aws_rds_cluster.secondary.cluster_identifier
}

output "secondary_cluster_arn" {
  description = "Secondary regional Aurora PostgreSQL cluster ARN."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_resource_id" {
  description = "Secondary regional Aurora PostgreSQL DbiResourceId used for IAM authentication."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_writer_endpoint" {
  description = "Secondary cluster endpoint (becomes the active writer endpoint upon regional failover promotion)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Secondary cluster reader endpoint."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "primary_security_group_id" {
  description = "Security group ID attached to the primary Aurora cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID attached to the secondary Aurora cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "Customer-managed KMS key ARN in the primary region."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "Customer-managed KMS key ARN in the secondary region."
  value       = aws_kms_key.secondary.arn
}

output "eks_db_connect_policy_arn" {
  description = "IAM policy ARN granting rds-db:connect for EKS workload IAM roles across both primary and secondary regions."
  value       = aws_iam_policy.eks_db_connect.arn
}

output "iam_db_users" {
  description = "PostgreSQL role names authorized in the EKS IAM database authentication policy."
  value       = local.iam_db_users
}

output "primary_alarm_sns_topic_arn" {
  description = "SNS topic ARN receiving primary region database alarms and RDS events."
  value       = local.primary_alarm_topic_arn
}

output "secondary_alarm_sns_topic_arn" {
  description = "SNS topic ARN receiving secondary region database alarms (including global replication lag) and RDS events."
  value       = local.secondary_alarm_topic_arn
}

output "primary_cloudwatch_log_group_name" {
  description = "CloudWatch log group name for primary cluster PostgreSQL audit/error logs."
  value       = aws_cloudwatch_log_group.primary.name
}

output "secondary_cloudwatch_log_group_name" {
  description = "CloudWatch log group name for secondary cluster PostgreSQL audit/error logs."
  value       = aws_cloudwatch_log_group.secondary.name
}
