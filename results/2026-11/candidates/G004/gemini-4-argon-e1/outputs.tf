output "global_cluster_id" {
  description = "The identifier of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "The ARN of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "The name of the initial PostgreSQL database."
  value       = aws_rds_cluster.primary.database_name
}

output "port" {
  description = "The PostgreSQL port on which the clusters accept connections."
  value       = aws_rds_cluster.primary.port
}

output "primary_cluster" {
  description = "Connection and resource details for the primary region Aurora PostgreSQL cluster."
  value = {
    region              = var.primary_region
    cluster_id          = aws_rds_cluster.primary.id
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    instance_endpoints  = aws_rds_cluster_instance.primary[*].endpoint
    security_group_id   = aws_security_group.primary.id
    db_subnet_group     = aws_db_subnet_group.primary.name
    kms_key_arn         = aws_kms_key.primary.arn
    vpc_id              = data.aws_vpc.primary.id
  }
}

output "secondary_cluster" {
  description = "Connection and resource details for the secondary region Aurora PostgreSQL cluster."
  value = {
    region              = var.secondary_region
    cluster_id          = aws_rds_cluster.secondary.id
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    instance_endpoints  = aws_rds_cluster_instance.secondary[*].endpoint
    security_group_id   = aws_security_group.secondary.id
    db_subnet_group     = aws_db_subnet_group.secondary.name
    kms_key_arn         = aws_kms_key.secondary.arn
    vpc_id              = data.aws_vpc.secondary.id
  }
}

output "master_user_secret" {
  description = "Secrets Manager details for the RDS-managed master user password."
  value       = aws_rds_cluster.primary.master_user_secret
}

output "iam_db_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect to both primary and secondary Aurora clusters for EKS service IAM roles."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_db_users" {
  description = "Database usernames permitted to authenticate via IAM database authentication under the generated IAM policy."
  value       = local.iam_db_users
}
