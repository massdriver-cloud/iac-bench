output "global_cluster_id" {
  description = "Identifier of the Aurora PostgreSQL Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the default PostgreSQL database created on the cluster."
  value       = aws_rds_cluster.primary.database_name
}

output "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept connections."
  value       = aws_rds_cluster.primary.port
}

output "iam_database_user" {
  description = "Database username configured in the IAM rds-db:connect authentication policy for EKS workloads."
  value       = local.iam_database_user
}

output "primary_cluster_id" {
  description = "Cluster identifier of the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "ARN of the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_resource_id" {
  description = "Region-unique DbiResourceId of the primary Aurora cluster (used for IAM database authentication)."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_writer_endpoint" {
  description = "Writer DNS endpoint for the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Load-balanced reader DNS endpoint for the primary Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "primary_instance_endpoints" {
  description = "List of individual instance DNS endpoints in the primary Aurora cluster."
  value       = aws_rds_cluster_instance.primary[*].endpoint
}

output "secondary_cluster_id" {
  description = "Cluster identifier of the secondary (DR) Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "ARN of the secondary (DR) Aurora PostgreSQL cluster."
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_resource_id" {
  description = "Region-unique DbiResourceId of the secondary Aurora cluster (used for IAM database authentication)."
  value       = aws_rds_cluster.secondary.cluster_resource_id
}

output "secondary_writer_endpoint" {
  description = "Writer DNS endpoint for the secondary Aurora cluster (active after global failover promotion)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Load-balanced reader DNS endpoint for the secondary Aurora cluster (supports local reads and global write forwarding)."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "secondary_instance_endpoints" {
  description = "List of individual instance DNS endpoints in the secondary Aurora cluster."
  value       = aws_rds_cluster_instance.secondary[*].endpoint
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret containing the RDS-managed master user credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "eks_iam_db_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect to both primary and secondary Aurora clusters for EKS service IAM roles."
  value       = aws_iam_policy.eks_iam_db_connect.arn
}

output "master_secret_read_policy_arn" {
  description = "ARN of the IAM policy granting read and KMS decrypt permissions for the RDS-managed master user secret."
  value       = aws_iam_policy.master_secret_read.arn
}

output "primary_security_group_id" {
  description = "Security group ID protecting the primary Aurora PostgreSQL cluster."
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "Security group ID protecting the secondary Aurora PostgreSQL cluster."
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting the primary cluster storage, logs, secrets, and Performance Insights."
  value       = aws_kms_key.primary.arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the customer-managed KMS key encrypting the secondary cluster storage, logs, and Performance Insights."
  value       = aws_kms_key.secondary.arn
}

output "primary_vpc_id" {
  description = "Discovered VPC ID in the primary region."
  value       = data.aws_vpc.primary.id
}

output "secondary_vpc_id" {
  description = "Discovered VPC ID in the secondary region."
  value       = data.aws_vpc.secondary.id
}

output "primary_db_subnet_group_name" {
  description = "Name of the DB subnet group created from tier=database subnets in the primary region."
  value       = aws_db_subnet_group.primary.name
}

output "secondary_db_subnet_group_name" {
  description = "Name of the DB subnet group created from tier=database subnets in the secondary region."
  value       = aws_db_subnet_group.secondary.name
}

output "global_replication_lag_alarm_arn" {
  description = "ARN of the CloudWatch alarm monitoring Aurora Global Database RPO replication lag."
  value       = aws_cloudwatch_metric_alarm.global_replication_lag.arn
}
