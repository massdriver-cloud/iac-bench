output "global_cluster_id" {
  description = "Identifier of the Aurora Global Database cluster connecting the primary and secondary regions."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database cluster."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the initial PostgreSQL database created in the cluster."
  value       = local.database_name
}

output "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept connections."
  value       = var.port
}

output "primary_cluster" {
  description = "Connection endpoints, identifiers, secret ARN, and network details for the primary region Aurora PostgreSQL cluster."
  value = {
    region              = var.primary_region
    vpc_id              = data.aws_vpc.primary.id
    subnet_ids          = data.aws_subnets.primary_database.ids
    cluster_id          = aws_rds_cluster.primary.id
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    instance_ids        = aws_rds_cluster_instance.primary[*].id
    instance_endpoints  = aws_rds_cluster_instance.primary[*].endpoint
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = aws_kms_key.primary.arn
    master_secret_arn   = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
  }
}

output "secondary_cluster" {
  description = "Connection endpoints, identifiers, and network details for the secondary region Aurora PostgreSQL standby cluster."
  value = {
    region              = var.secondary_region
    vpc_id              = data.aws_vpc.secondary.id
    subnet_ids          = data.aws_subnets.secondary_database.ids
    cluster_id          = aws_rds_cluster.secondary.id
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    instance_ids        = aws_rds_cluster_instance.secondary[*].id
    instance_endpoints  = aws_rds_cluster_instance.secondary[*].endpoint
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = aws_kms_key.secondary.arn
  }
}

output "iam_db_connect_policy_arn" {
  description = "ARN of the IAM policy granting rds-db:connect permissions for the service's database users across both primary and secondary regional clusters. Attach this policy to the service's EKS IAM role (IRSA / Pod Identity)."
  value       = aws_iam_policy.iam_db_connect.arn
}

output "master_user_secret_arn" {
  description = "ARN of the AWS Secrets Manager secret managing the master database credentials."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}
