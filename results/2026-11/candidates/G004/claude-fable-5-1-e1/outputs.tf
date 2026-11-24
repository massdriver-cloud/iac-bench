output "global_cluster_identifier" {
  description = "Identifier of the Aurora Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

output "port" {
  description = "PostgreSQL port."
  value       = 5432
}

output "primary" {
  description = "Primary-region cluster details. Applications in this region connect to writer_endpoint for writes and reader_endpoint for reads."
  value = {
    region              = var.primary_region
    cluster_identifier  = aws_rds_cluster.primary.cluster_identifier
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = aws_kms_key.primary.arn
    instance_ids        = aws_rds_cluster_instance.primary[*].identifier
  }
}

output "secondary" {
  description = "Secondary-region cluster details. Read-only until promoted; with write forwarding enabled, writes sent to writer_endpoint are forwarded to the primary."
  value = {
    region              = var.secondary_region
    cluster_identifier  = aws_rds_cluster.secondary.cluster_identifier
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = aws_kms_key.secondary.arn
    instance_ids        = aws_rds_cluster_instance.secondary[*].identifier
  }
}

output "master_user_secret_arn" {
  description = "Secrets Manager secret holding the break-glass master credentials (managed and rotated by RDS)."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "master_username" {
  description = "Master username."
  value       = var.master_username
}

output "application_connect_policy_arn" {
  description = "IAM policy granting rds-db:connect for application_db_users on both clusters. Attach to the EKS service's IAM role."
  value       = aws_iam_policy.app_connect.arn
}

output "application_db_users" {
  description = "PostgreSQL roles the connect policy covers. Create each with: CREATE ROLE <name> WITH LOGIN; GRANT rds_iam TO <name>;"
  value       = var.application_db_users
}

output "failover_runbook" {
  description = "How to fail over to the secondary region."
  value       = <<-EOT
    Planned switchover (zero data loss):
      aws rds switchover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} \
        --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --region ${var.primary_region}

    Unplanned failover (primary region unavailable; loses at most the current replication lag):
      aws rds failover-global-cluster --global-cluster-identifier ${aws_rds_global_cluster.this.id} \
        --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss --region ${var.secondary_region}

    Afterwards point services at the ${var.secondary_region} writer endpoint (${aws_rds_cluster.secondary.endpoint}).
    Then swap primary_region/secondary_region in your tfvars and run a plan to realign state.
  EOT
}
