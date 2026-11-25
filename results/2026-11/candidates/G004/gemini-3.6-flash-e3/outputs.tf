output "global_cluster_id" {
  description = "The Aurora Global Cluster ID"
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "The Aurora Global Cluster ARN"
  value       = aws_rds_global_cluster.this.arn
}

output "primary_cluster_id" {
  description = "The ID of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.id
}

output "primary_cluster_arn" {
  description = "The ARN of the primary Aurora cluster"
  value       = aws_rds_cluster.primary.arn
}

output "primary_cluster_endpoint" {
  description = "Writer endpoint for the primary Aurora cluster"
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_cluster_reader_endpoint" {
  description = "Reader endpoint for the primary Aurora cluster"
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_cluster_id" {
  description = "The ID of the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.id
}

output "secondary_cluster_arn" {
  description = "The ARN of the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.arn
}

output "secondary_cluster_endpoint" {
  description = "Writer endpoint for the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_cluster_reader_endpoint" {
  description = "Reader endpoint for the secondary Aurora cluster"
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "primary_security_group_id" {
  description = "ID of the security group created for the primary Aurora cluster"
  value       = aws_security_group.primary.id
}

output "secondary_security_group_id" {
  description = "ID of the security group created for the secondary Aurora cluster"
  value       = aws_security_group.secondary.id
}

output "primary_kms_key_arn" {
  description = "ARN of the KMS key used in the primary region"
  value       = local.primary_kms_key_arn
}

output "secondary_kms_key_arn" {
  description = "ARN of the KMS key used in the secondary region"
  value       = local.secondary_kms_key_arn
}

output "master_user_secret_arn" {
  description = "ARN of the master user secret created in AWS Secrets Manager (if managed)"
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}
