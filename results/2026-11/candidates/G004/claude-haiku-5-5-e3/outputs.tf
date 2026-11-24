output "global_cluster_identifier" {
  description = "Aurora Global Database identifier."
  value       = aws_rds_global_cluster.this.id
}

output "writer_region" {
  description = "Region that the writer DNS record currently points to."
  value       = var.writer_region == "primary" ? var.primary_region : var.secondary_region
}

output "writer_endpoint" {
  description = "Writer endpoint of the cluster selected by writer_region."
  value       = local.writer_endpoint
}

output "primary" {
  description = "Primary regional cluster details."
  value = {
    region           = var.primary_region
    cluster_id       = aws_rds_cluster.primary.id
    cluster_resource = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint  = aws_rds_cluster.primary.endpoint
    reader_endpoint  = aws_rds_cluster.primary.reader_endpoint
    port             = aws_rds_cluster.primary.port
    kms_key_arn      = aws_kms_key.primary.arn
    master_secret    = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
    vpc_id           = data.aws_vpc.primary.id
    subnet_ids       = data.aws_subnets.primary_database.ids
  }
}

output "secondary" {
  description = "Secondary regional cluster details."
  value = {
    region           = var.secondary_region
    cluster_id       = aws_rds_cluster.secondary.id
    cluster_resource = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint  = aws_rds_cluster.secondary.endpoint
    reader_endpoint  = aws_rds_cluster.secondary.reader_endpoint
    port             = aws_rds_cluster.secondary.port
    kms_key_arn      = aws_kms_key.secondary.arn
    vpc_id           = data.aws_vpc.secondary.id
    subnet_ids       = data.aws_subnets.secondary_database.ids
  }
}

output "db_connect_policy_arn" {
  description = "Managed policy granting rds-db:connect as iam_db_user in both regions. Attach it to any role that is not listed in app_iam_role_names."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_db_user" {
  description = "Database user used for IAM authentication."
  value       = var.iam_db_user
}
