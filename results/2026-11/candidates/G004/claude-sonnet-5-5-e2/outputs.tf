output "global_cluster_id" {
  description = "Aurora Global Database identifier. For a regional failover, run: aws rds failover-global-cluster --global-cluster-identifier <id> --target-db-cluster-identifier <secondary_cluster_arn> --region <secondary_region> (use switchover-global-cluster for planned moves)."
  value       = aws_rds_global_cluster.this.id
}

output "primary_cluster_arn" {
  description = "ARN of the cluster in the primary region."
  value       = aws_rds_cluster.primary.arn
}

output "secondary_cluster_arn" {
  description = "ARN of the cluster in the secondary region (failover target)."
  value       = aws_rds_cluster.secondary.arn
}

output "primary_writer_endpoint" {
  description = "Cluster (writer) endpoint in the primary region."
  value       = aws_rds_cluster.primary.endpoint
}

output "primary_reader_endpoint" {
  description = "Reader endpoint in the primary region."
  value       = aws_rds_cluster.primary.reader_endpoint
}

output "secondary_writer_endpoint" {
  description = "Cluster endpoint in the secondary region; becomes the writer endpoint after failover (read-only before)."
  value       = aws_rds_cluster.secondary.endpoint
}

output "secondary_reader_endpoint" {
  description = "Reader endpoint in the secondary region."
  value       = aws_rds_cluster.secondary.reader_endpoint
}

output "port" {
  description = "PostgreSQL port."
  value       = aws_rds_cluster.primary.port
}

output "database_name" {
  description = "Initial database name."
  value       = var.database_name
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret (primary region) holding the master credentials. Prefer IAM database authentication for applications."
  value       = aws_rds_cluster.primary.master_user_secret[0].secret_arn
}

output "kms_key_arns" {
  description = "KMS keys encrypting the data in each region."
  value = {
    primary   = aws_kms_key.primary.arn
    secondary = aws_kms_key.secondary.arn
  }
}

output "security_group_ids" {
  description = "Database security groups per region."
  value = {
    primary   = aws_security_group.primary.id
    secondary = aws_security_group.secondary.id
  }
}
