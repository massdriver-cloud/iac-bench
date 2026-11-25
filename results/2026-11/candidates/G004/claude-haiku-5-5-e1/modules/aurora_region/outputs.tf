output "region" {
  description = "Region this cluster runs in."
  value       = data.aws_region.current.name
}

output "cluster_id" {
  description = "Regional cluster identifier."
  value       = aws_rds_cluster.this.id
}

output "cluster_arn" {
  description = "Regional cluster ARN."
  value       = aws_rds_cluster.this.arn
}

output "global_cluster_identifier" {
  description = "Global cluster this regional cluster belongs to. Consumers that must wait for this cluster to join the global database reference this output."
  value       = aws_rds_cluster.this.global_cluster_identifier
}

output "cluster_resource_id" {
  description = "Cluster resource ID, used in rds-db:connect ARNs for IAM database authentication."
  value       = aws_rds_cluster.this.cluster_resource_id
}

output "writer_endpoint" {
  description = "Cluster (writer) endpoint. Only accepts writes while this cluster is the primary."
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "Reader endpoint for this region's cluster."
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.this.port
}

output "kms_key_arn" {
  description = "Customer-managed KMS key ARN for this region."
  value       = aws_kms_key.this.arn
}

output "security_group_id" {
  description = "Security group guarding this cluster."
  value       = aws_security_group.this.id
}

output "master_user_secret_arn" {
  description = "Secrets Manager ARN of the master password (primary only; null on secondary)."
  value       = try(aws_rds_cluster.this.master_user_secret[0].secret_arn, null)
}

output "replication_lag_alarm_name" {
  description = "Replication-lag alarm name (secondary only; null on primary)."
  value       = try(aws_cloudwatch_metric_alarm.replication_lag[0].alarm_name, null)
}
