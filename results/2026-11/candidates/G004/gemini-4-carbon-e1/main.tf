# -----------------------------------------------------------------------------
# Encrypted CloudWatch Log Groups for Database & IAM Auth Audit Logs
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary" {
  for_each = toset(local.cloudwatch_log_exports)

  region            = var.primary_region
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-${each.value}-logs"
  })
}

resource "aws_cloudwatch_log_group" "secondary" {
  for_each = toset(local.cloudwatch_log_exports)

  region            = var.secondary_region
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-${each.value}-logs"
  })
}

# -----------------------------------------------------------------------------
# Aurora PostgreSQL Global Database (Sub-Second RPO, Minutes-Level RTO)
# -----------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  region                    = var.primary_region
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = merge(local.tags, {
    Name = local.global_cluster_id
  })

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region (${var.primary_region}) and secondary_region (${var.secondary_region}) must be two distinct US AWS regions."
    }

    precondition {
      condition     = data.aws_rds_engine_version.primary.supports_global_databases && data.aws_rds_engine_version.secondary.supports_global_databases
      error_message = "Selected Aurora PostgreSQL version ${local.engine_version} must support Aurora Global Database in both ${var.primary_region} and ${var.secondary_region}."
    }
  }
}

# -----------------------------------------------------------------------------
# Primary Region Aurora Cluster & Multi-AZ Instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  region                          = var.primary_region
  cluster_identifier              = local.primary_cluster_id
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  database_name                   = local.database_name
  master_username                 = var.master_username
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = aws_kms_key.primary.arn
  port                            = var.port
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.db_primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = !var.final_snapshot_enabled
  final_snapshot_identifier    = var.final_snapshot_enabled ? "${local.primary_cluster_id}-final" : null

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.tags, {
    Name = local.primary_cluster_id
    role = "primary"
  })

  depends_on = [aws_cloudwatch_log_group.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  region                  = var.primary_region
  identifier              = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.primary.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.primary.engine
  engine_version          = aws_rds_cluster.primary.engine_version
  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name

  publicly_accessible        = false
  promotion_tier             = count.index == 0 ? 0 : 1
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  copy_tags_to_snapshot      = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-${count.index + 1}"
  })

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}

# -----------------------------------------------------------------------------
# Secondary Region Warm Aurora Cluster & Multi-AZ Instances
# -----------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  region                          = var.secondary_region
  cluster_identifier              = local.secondary_cluster_id
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  port                            = var.port
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.db_secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = var.apply_immediately
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection

  # AWS RDS API forbids final snapshots on unpromoted Global Database secondary clusters;
  # snapshots and 35-day PITR backups are retained on the primary cluster and continuous backups.
  skip_final_snapshot = true

  enabled_cloudwatch_logs_exports = local.cloudwatch_log_exports

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.is_serverless ? [var.serverlessv2_scaling] : []
    content {
      min_capacity = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity = serverlessv2_scaling_configuration.value.max_capacity
    }
  }

  tags = merge(local.tags, {
    Name = local.secondary_cluster_id
    role = "secondary"
  })

  # AWS requires at least one instance on the primary cluster before attaching a secondary cluster.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  count = var.secondary_instance_count

  region                  = var.secondary_region
  identifier              = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier      = aws_rds_cluster.secondary.id
  instance_class          = var.instance_class
  engine                  = aws_rds_cluster.secondary.engine
  engine_version          = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name

  publicly_accessible        = false
  promotion_tier             = count.index == 0 ? 0 : 1
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  apply_immediately          = var.apply_immediately
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  copy_tags_to_snapshot      = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-${count.index + 1}"
  })

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
