###############################################################################
# Connecting
###############################################################################

output "global_writer_endpoint" {
  description = "Hostname that always points at the current writer, in whichever region it is. It follows the writer automatically after a switchover or failover; needs a network path to the writer's region."
  value       = aws_rds_global_cluster.this.endpoint
}

output "regional_endpoints" {
  description = "Per-region cluster endpoints. Services should connect to the endpoints of their own region: in the writer region `writer` takes writes directly; in the standby region connections are read-only unless the session enables write forwarding (SET apg_write_forward.consistency_mode)."
  value = {
    (var.primary_region) = {
      writer = aws_rds_cluster.primary.endpoint
      reader = aws_rds_cluster.primary.reader_endpoint
    }
    (var.secondary_region) = {
      writer = aws_rds_cluster.secondary.endpoint
      reader = aws_rds_cluster.secondary.reader_endpoint
    }
  }
}

output "port" {
  description = "PostgreSQL port."
  value       = local.port
}

output "database_name" {
  description = "Name of the initial database."
  value       = local.database_name
}

###############################################################################
# Access
###############################################################################

output "app_db_username" {
  description = "Database user services log in as with IAM authentication (create once: CREATE USER <name>; GRANT rds_iam TO <name>;)."
  value       = var.app_db_username
}

output "db_connect_policy_arn" {
  description = "IAM policy allowing IAM-authenticated login as app_db_username in both regions. Already attached to app_iam_role_names."
  value       = aws_iam_policy.db_connect.arn
}

output "master_secret_arn" {
  description = "Secrets Manager secret (primary region) holding the break-glass administrator credentials. A replica with the same name exists in the secondary region."
  value       = aws_secretsmanager_secret.master.arn
}

output "master_secret_name" {
  description = "Name of the administrator credentials secret, identical in both regions."
  value       = aws_secretsmanager_secret.master.name
}

output "security_group_ids" {
  description = "Security group attached to the database in each region."
  value = {
    (var.primary_region)   = module.primary.security_group_id
    (var.secondary_region) = module.secondary.security_group_id
  }
}

###############################################################################
# Identifiers
###############################################################################

output "global_cluster_id" {
  description = "Identifier of the Aurora global database."
  value       = aws_rds_global_cluster.this.id
}

output "cluster_arns" {
  description = "ARN of the regional cluster in each region."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.arn
    (var.secondary_region) = aws_rds_cluster.secondary.arn
  }
}

output "cluster_identifiers" {
  description = "Identifier of the regional cluster in each region."
  value = {
    (var.primary_region)   = aws_rds_cluster.primary.cluster_identifier
    (var.secondary_region) = aws_rds_cluster.secondary.cluster_identifier
  }
}

output "kms_key_arns" {
  description = "Customer-managed KMS key protecting the database in each region."
  value = {
    (var.primary_region)   = module.primary.kms_key_arn
    (var.secondary_region) = module.secondary.kms_key_arn
  }
}

output "log_group_names" {
  description = "CloudWatch log group with PostgreSQL and audit logs in each region."
  value = {
    (var.primary_region)   = module.primary.log_group_name
    (var.secondary_region) = module.secondary.log_group_name
  }
}

output "replication_lag_alarm_arns" {
  description = "Replication-lag alarm in each region."
  value = {
    (var.primary_region)   = module.primary.replication_lag_alarm_arn
    (var.secondary_region) = module.secondary.replication_lag_alarm_arn
  }
}

###############################################################################
# Runbook
###############################################################################

output "regional_failover_command" {
  description = "Run this when the primary region is down. Promotes the secondary region to writer; may lose the last moments of un-replicated writes (bounded by managed_rpo_seconds)."
  value       = "aws rds failover-global-cluster --region ${var.secondary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn} --allow-data-loss"
}

output "regional_switchover_command" {
  description = "Planned, zero-data-loss move of the writer to the secondary region (for drills and maintenance). Both regions must be healthy."
  value       = "aws rds switchover-global-cluster --region ${var.primary_region} --global-cluster-identifier ${aws_rds_global_cluster.this.id} --target-db-cluster-identifier ${aws_rds_cluster.secondary.arn}"
}
