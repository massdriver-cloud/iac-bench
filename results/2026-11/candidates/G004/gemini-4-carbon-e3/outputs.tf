output "global_cluster_identifier" {
  description = "Identifier of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.id
}

output "global_cluster_arn" {
  description = "ARN of the Aurora PostgreSQL Global Database."
  value       = aws_rds_global_cluster.this.arn
}

output "global_writer_endpoint" {
  description = "Aurora Global Database writer endpoint (automatically tracks the active primary region across switchovers and failovers)."
  value       = try(aws_rds_global_cluster.this.endpoint, null)
}

output "database_name" {
  description = "Initial PostgreSQL database name created in the cluster."
  value       = local.database_name
}

output "port" {
  description = "TCP port on which the Aurora PostgreSQL clusters accept TLS connections."
  value       = var.port
}

output "engine_version" {
  description = "Actual Aurora PostgreSQL engine version deployed across both regions."
  value       = local.engine_version
}

output "primary_cluster" {
  description = "Connection, network, and security metadata for the primary regional Aurora cluster."
  value = {
    region              = var.primary_region
    cluster_identifier  = aws_rds_cluster.primary.id
    cluster_arn         = aws_rds_cluster.primary.arn
    cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.primary.endpoint
    reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
    instance_ids        = aws_rds_cluster_instance.primary[*].id
    security_group_id   = aws_security_group.primary.id
    kms_key_arn         = local.primary_kms_key_arn
    vpc_id              = data.aws_vpc.primary.id
    subnet_ids          = sort(data.aws_subnets.primary_database.ids)
  }
}

output "secondary_cluster" {
  description = "Connection, network, and security metadata for the warm secondary regional Aurora cluster."
  value = {
    region              = var.secondary_region
    cluster_identifier  = aws_rds_cluster.secondary.id
    cluster_arn         = aws_rds_cluster.secondary.arn
    cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
    writer_endpoint     = aws_rds_cluster.secondary.endpoint
    reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
    instance_ids        = aws_rds_cluster_instance.secondary[*].id
    security_group_id   = aws_security_group.secondary.id
    kms_key_arn         = local.secondary_kms_key_arn
    vpc_id              = data.aws_vpc.secondary.id
    subnet_ids          = sort(data.aws_subnets.secondary_database.ids)
  }
}

output "endpoints_by_region" {
  description = "Map of regional Aurora endpoints keyed by AWS region for EKS service configuration in each US region."
  value = {
    (var.primary_region) = {
      writer_endpoint     = aws_rds_cluster.primary.endpoint
      reader_endpoint     = aws_rds_cluster.primary.reader_endpoint
      cluster_resource_id = aws_rds_cluster.primary.cluster_resource_id
      port                = var.port
    }
    (var.secondary_region) = {
      writer_endpoint     = aws_rds_cluster.secondary.endpoint
      reader_endpoint     = aws_rds_cluster.secondary.reader_endpoint
      cluster_resource_id = aws_rds_cluster.secondary.cluster_resource_id
      port                = var.port
    }
  }
}

output "iam_connect_policy_arn" {
  description = "ARN of the managed IAM policy granting rds-db:connect across both primary and secondary regional clusters (attach to EKS IRSA / Pod Identity roles)."
  value       = aws_iam_policy.db_connect.arn
}

output "iam_database_users" {
  description = "PostgreSQL database role names permitted for IAM token authentication by iam_connect_policy_arn (grant rds_iam to these roles inside PostgreSQL)."
  value       = local.iam_db_users
}

output "master_user_secret_arn" {
  description = "ARN of the KMS-encrypted AWS Secrets Manager secret storing the AWS-managed master user password."
  value       = try(aws_rds_cluster.primary.master_user_secret[0].secret_arn, null)
}

output "dns_endpoints" {
  description = "Custom Route 53 DNS endpoints when route53_zone_id and route53_domain_suffix are configured."
  value = var.route53_zone_id != null && var.route53_domain_suffix != null ? {
    writer           = aws_route53_record.writer[0].fqdn
    primary_reader   = aws_route53_record.primary_reader[0].fqdn
    secondary_reader = aws_route53_record.secondary_reader[0].fqdn
  } : null
}

output "failover_runbook_commands" {
  description = "Pre-populated AWS CLI commands for planned zero-data-loss regional switchover and unplanned regional outage failover."
  value = {
    planned_switchover = "aws rds switchover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
    unplanned_failover = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
  }
}
