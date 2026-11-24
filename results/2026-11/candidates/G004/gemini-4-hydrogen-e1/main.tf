resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = data.aws_rds_engine_version.primary.version
  storage_encrypted         = true
  deletion_protection       = local.deletion_protection

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be different US AWS regions for regional disaster recovery."
    }

    precondition {
      condition     = length(data.aws_subnets.primary_db.ids) >= 2
      error_message = "Primary VPC ${local.vpc_name} in ${var.primary_region} must have at least 2 subnets tagged tier=database."
    }

    precondition {
      condition     = length(data.aws_subnets.secondary_db.ids) >= 2
      error_message = "Secondary VPC ${local.vpc_name} in ${var.secondary_region} must have at least 2 subnets tagged tier=database."
    }

    precondition {
      condition     = var.serverlessv2_max_capacity >= var.serverlessv2_min_capacity
      error_message = "serverlessv2_max_capacity must be >= serverlessv2_min_capacity."
    }
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name_prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  engine_mode                         = "provisioned"
  storage_type                        = var.storage_type
  port                                = var.port
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  db_instance_parameter_group_name    = aws_db_parameter_group.primary.name
  iam_database_authentication_enabled = true
  backup_retention_period             = local.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = local.deletion_protection
  skip_final_snapshot                 = local.skip_final_snapshot
  final_snapshot_identifier           = local.skip_final_snapshot ? null : "${local.name_prefix}-primary-final"
  copy_tags_to_snapshot               = true
  allow_major_version_upgrade         = false
  apply_immediately                   = local.apply_immediately

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.primary_is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  depends_on = [
    aws_cloudwatch_log_group.primary,
    aws_kms_key.primary,
  ]
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = "${local.name_prefix}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  engine_mode                         = "provisioned"
  storage_type                        = var.storage_type
  port                                = var.port
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  db_instance_parameter_group_name    = aws_db_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  enable_global_write_forwarding      = var.enable_global_write_forwarding
  backup_retention_period             = local.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  deletion_protection                 = local.deletion_protection
  skip_final_snapshot                 = true
  copy_tags_to_snapshot               = true
  allow_major_version_upgrade         = false
  apply_immediately                   = local.apply_immediately

  dynamic "serverlessv2_scaling_configuration" {
    for_each = local.secondary_is_serverless ? [1] : []
    content {
      min_capacity = var.serverlessv2_min_capacity
      max_capacity = var.serverlessv2_max_capacity
    }
  }

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
    ]
  }

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
    aws_kms_key.secondary,
  ]
}
