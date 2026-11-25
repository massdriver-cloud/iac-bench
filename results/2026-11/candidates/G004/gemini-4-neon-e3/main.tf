# ------------------------------------------------------------------------------
# Aurora PostgreSQL Global Database (RPO ~1s, RTO < 1 min across US regions)
# ------------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region (${var.primary_region}) and secondary_region (${var.secondary_region}) must be different US AWS regions for regional disaster recovery."
    }
  }
}

# ------------------------------------------------------------------------------
# Primary Regional Aurora Cluster & Multi-AZ Instances
# ------------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.primary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  storage_type   = var.storage_type
  port           = var.port

  database_name                 = aws_rds_global_cluster.this.database_name
  master_username               = var.master_username
  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = var.skip_final_snapshot
  final_snapshot_identifier   = var.skip_final_snapshot ? null : "${local.primary_cluster_id}-final"
  apply_immediately           = var.apply_immediately
  allow_major_version_upgrade = false

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [replication_source_identifier]

    precondition {
      condition     = data.aws_rds_engine_version.primary.supports_global_databases
      error_message = "Aurora PostgreSQL engine version ${var.engine_version} does not support Aurora Global Databases in ${var.primary_region}."
    }
  }

  depends_on = [aws_cloudwatch_log_group.primary_postgresql]

  tags = {
    Name        = local.primary_cluster_id
    ClusterRole = "primary"
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id

  instance_class = var.instance_class
  engine         = aws_rds_cluster.primary.engine
  engine_version = aws_rds_cluster.primary.engine_version

  db_subnet_group_name    = aws_db_subnet_group.primary.name
  db_parameter_group_name = aws_db_parameter_group.primary.name
  availability_zone       = local.primary_azs[count.index % length(local.primary_azs)]
  promotion_tier          = count.index

  publicly_accessible        = false
  ca_cert_identifier         = var.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  copy_tags_to_snapshot      = true
  apply_immediately          = var.apply_immediately

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.primary.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  tags = {
    Name        = "${local.primary_cluster_id}-${count.index + 1}"
    ClusterRole = "primary"
  }
}

# ------------------------------------------------------------------------------
# Secondary Regional Aurora Cluster & Warm Multi-AZ Replica Instances
# ------------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id

  engine         = aws_rds_global_cluster.this.engine
  engine_version = aws_rds_global_cluster.this.engine_version
  storage_type   = var.storage_type
  port           = var.port

  enable_global_write_forwarding = var.enable_global_write_forwarding

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  # Configured identically so backup retention applies immediately if promoted during DR
  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  # Secondary clusters in an Aurora Global Database cannot take a final snapshot while attached
  deletion_protection         = var.deletion_protection
  skip_final_snapshot         = true
  apply_immediately           = var.apply_immediately
  allow_major_version_upgrade = false

  enabled_cloudwatch_logs_exports = ["postgresql"]

  lifecycle {
    ignore_changes = [replication_source_identifier]

    precondition {
      condition     = data.aws_rds_engine_version.secondary.supports_global_databases
      error_message = "Aurora PostgreSQL engine version ${var.engine_version} does not support Aurora Global Databases in ${var.secondary_region}."
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.secondary_postgresql,
    aws_rds_cluster_instance.primary,
  ]

  tags = {
    Name        = local.secondary_cluster_id
    ClusterRole = "secondary"
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id

  instance_class = local.secondary_instance_class
  engine         = aws_rds_cluster.secondary.engine
  engine_version = aws_rds_cluster.secondary.engine_version

  db_subnet_group_name    = aws_db_subnet_group.secondary.name
  db_parameter_group_name = aws_db_parameter_group.secondary.name
  availability_zone       = local.secondary_azs[count.index % length(local.secondary_azs)]
  promotion_tier          = count.index

  publicly_accessible        = false
  ca_cert_identifier         = var.ca_cert_identifier
  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  copy_tags_to_snapshot      = true
  apply_immediately          = var.apply_immediately

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.enhanced_monitoring[0].arn : null

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.secondary.arn : null
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  tags = {
    Name        = "${local.secondary_cluster_id}-${count.index + 1}"
    ClusterRole = "secondary"
  }
}
