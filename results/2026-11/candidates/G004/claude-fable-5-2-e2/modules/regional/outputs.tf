output "vpc_id" {
  description = "VPC the database is placed in."
  value       = data.aws_vpc.this.id
}

output "subnet_ids" {
  description = "Database subnets used."
  value       = data.aws_subnets.database.ids
}

output "db_subnet_group_name" {
  description = "DB subnet group name."
  value       = aws_db_subnet_group.this.name
}

output "security_group_id" {
  description = "Security group attached to the cluster."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "Customer-managed KMS key for this region."
  value       = aws_kms_key.this.arn
}

output "cluster_parameter_group_name" {
  description = "Cluster parameter group name."
  value       = aws_rds_cluster_parameter_group.this.name
}

output "log_group_name" {
  description = "CloudWatch log group receiving PostgreSQL logs."
  value       = aws_cloudwatch_log_group.postgresql.name
}

output "replication_lag_alarm_arn" {
  description = "ARN of the replication-lag alarm."
  value       = aws_cloudwatch_metric_alarm.replication_lag.arn
}
