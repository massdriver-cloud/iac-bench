resource "aws_rds_global_cluster" "this" {
  provider                  = aws.primary
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = data.aws_rds_engine_version.postgresql.version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-global"
  })
}

resource "aws_rds_cluster" "primary" {
  provider                            = aws.primary
  cluster_identifier                  = "${local.name_prefix}-${var.primary_region}"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.key_id
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.name_prefix}-${var.primary_region}-final-snapshot"
  apply_immediately                   = var.apply_immediately
  enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      min_capacity             = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity             = serverlessv2_scaling_configuration.value.max_capacity
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.seconds_until_auto_pause
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}"
    Region = var.primary_region
    Role   = "primary"
  })

  depends_on = [
    aws_cloudwatch_log_group.primary_postgresql,
    aws_cloudwatch_log_group.primary_iam_auth
  ]
}

resource "aws_rds_cluster_instance" "primary" {
  provider                              = aws.primary
  count                                 = var.primary_instance_count
  identifier                            = "${local.name_prefix}-${var.primary_region}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  apply_immediately                     = var.apply_immediately
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  ca_cert_identifier                    = "rds-ca-ecc384-g1"
  copy_tags_to_snapshot                 = true
  promotion_tier                        = count.index == 0 ? 0 : 1

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-${count.index + 1}"
    Region = var.primary_region
    Role   = count.index == 0 ? "writer" : "reader"
  })
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name_prefix}-${var.secondary_region}"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  port                                = var.port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_type                        = var.storage_type
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.name_prefix}-${var.secondary_region}-final-snapshot"
  apply_immediately                   = var.apply_immediately
  enabled_cloudwatch_logs_exports     = ["postgresql", "iam-db-auth-error"]
  source_region                       = var.primary_region

  dynamic "serverlessv2_scaling_configuration" {
    for_each = var.serverlessv2_scaling_configuration != null ? [var.serverlessv2_scaling_configuration] : []
    content {
      min_capacity             = serverlessv2_scaling_configuration.value.min_capacity
      max_capacity             = serverlessv2_scaling_configuration.value.max_capacity
      seconds_until_auto_pause = serverlessv2_scaling_configuration.value.seconds_until_auto_pause
    }
  }

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}"
    Region = var.secondary_region
    Role   = "secondary"
  })

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary_postgresql,
    aws_cloudwatch_log_group.secondary_iam_auth
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier
    ]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = var.secondary_instance_count
  identifier                            = "${local.name_prefix}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  apply_immediately                     = var.apply_immediately
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  ca_cert_identifier                    = "rds-ca-ecc384-g1"
  copy_tags_to_snapshot                 = true
  promotion_tier                        = count.index == 0 ? 0 : 1

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-${count.index + 1}"
    Region = var.secondary_region
    Role   = "standby-reader"
  })
}
