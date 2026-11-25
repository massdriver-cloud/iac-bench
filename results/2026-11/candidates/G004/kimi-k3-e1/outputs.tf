output "global_cluster_id" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora global database."
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint of the primary cluster. Services read and write here until a switchover."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Load-balanced read endpoint of the primary cluster."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_endpoint" {
  description = "Endpoint of the standby cluster. Read-only while it is a secondary; it becomes the writer endpoint after a switchover."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Load-balanced read endpoint of the standby cluster, usable for cross-region read traffic."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "database_name" {
  description = "Name of the initial database."
  value       = var.database_name
}

output "port" {
  description = "Port the clusters listen on."
  value       = var.port
}

output "master_username" {
  description = "Master username. The password lives in the Secrets Manager secret referenced by master_user_secret_arn."
  value       = var.master_username
}

output "master_user_secret_arn" {
  description = "ARN of the Secrets Manager secret (primary region) holding the RDS-managed master password."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "iam_auth_cluster_resource_id" {
  description = "Resource ID of the primary cluster, used to build rds-db:connect IAM policy ARNs (arn:aws:rds-db:<region>:<account>:dbuser:<this-value>/<db-user>) for IAM database authentication."
  value       = aws_rds_cluster.primary.cluster_resource_id
}

output "primary_security_group_id" {
  description = "Security group protecting the primary cluster."
  value       = module.primary_region.security_group_id
}

output "secondary_security_group_id" {
  description = "Security group protecting the secondary cluster."
  value       = module.secondary_region.security_group_id
}

output "primary_kms_key_arn" {
  description = "ARN of the customer managed KMS key encrypting the primary cluster."
  value       = module.primary_region.kms_key_arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the customer managed KMS key encrypting the secondary cluster."
  value       = module.secondary_region.kms_key_arn
}

output "discovered_network" {
  description = "Networking the module discovered by tag in each region. Empty values mean the tagged VPC/subnets do not exist yet; create them before applying."
  value = {
    primary = {
      vpc_id              = module.primary_region.vpc_id
      database_subnet_ids = module.primary_region.database_subnet_ids
    }
    secondary = {
      vpc_id              = module.secondary_region.vpc_id
      database_subnet_ids = module.secondary_region.database_subnet_ids
    }
  }
}

output "switchover_command" {
  description = "AWS CLI command for a managed, zero-data-loss switchover of the global database to the secondary region (writer is typically serving again within about a minute)."
  value       = "aws rds switchover-global-cluster --region ${var.primary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}
