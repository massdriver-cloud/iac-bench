output "vpc_id" {
  description = "ID of the discovered VPC (null when no VPC matched)."
  value       = local.vpc_id
}

output "vpc_cidr_block" {
  description = "CIDR block of the discovered VPC (null when no VPC matched)."
  value       = local.vpc_cidr_block
}

output "database_subnet_ids" {
  description = "IDs of the discovered private database subnets."
  value       = local.database_subnet_ids
}

output "subnet_group_name" {
  description = "Name of the DB subnet group."
  value       = aws_db_subnet_group.this.name
}

output "security_group_id" {
  description = "ID of the cluster security group."
  value       = aws_security_group.this.id
}

output "kms_key_arn" {
  description = "ARN of the regional customer managed KMS key."
  value       = aws_kms_key.this.arn
}

output "cluster_parameter_group_name" {
  description = "Name of the cluster parameter group."
  value       = aws_rds_cluster_parameter_group.this.name
}
