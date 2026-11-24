locals {
  cluster_parameters = {
    "rds.force_ssl" = { value = "1", apply_method = "pending-reboot" }
    # 20 seconds is the minimum nonzero Aurora setting, not the RPO objective.
    "rds.global_db_rpo"       = { value = "20", apply_method = "immediate" }
    "log_statement"           = { value = "none", apply_method = "immediate" }
    "log_min_error_statement" = { value = "panic", apply_method = "immediate" }
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.primary_id}-pg16"
  family      = "aurora-postgresql16"
  description = "TLS, logging, and global RPO guardrail for ${local.primary_id}"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.secondary_id}-pg16"
  family      = "aurora-postgresql16"
  description = "TLS, logging, and global RPO guardrail for ${local.secondary_id}"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier              = local.primary_id
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = var.engine_version
  engine_mode                     = "provisioned"
  database_name                   = local.database_name
  master_username                 = local.admin_user
  master_password_wo              = jsondecode(ephemeral.aws_secretsmanager_secret_version.admin.secret_string).password
  master_password_wo_version      = 1
  port                            = local.port
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.primary.arn
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "05:00-06:00"
  preferred_maintenance_window        = "sun:06:00-sun:07:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.primary_id}-final"
  apply_immediately                   = false

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    # RDS automatically manages this association when a member changes role.
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider                        = aws.secondary
  cluster_identifier              = local.secondary_id
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = var.engine_version
  engine_mode                     = "provisioned"
  port                            = local.port
  source_region                   = var.primary_region
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.secondary.arn
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "07:00-08:00"
  preferred_maintenance_window        = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.secondary_id}-final"
  enable_global_write_forwarding      = false
  apply_immediately                   = false

  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]

  lifecycle {
    ignore_changes = [replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count                           = 2
  identifier                      = "${local.primary_id}-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  engine                          = aws_rds_cluster.primary.engine
  instance_class                  = var.instance_class
  availability_zone               = try(local.primary_azs[count.index], null)
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  promotion_tier                  = count.index
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                        = aws.secondary
  count                           = 2
  identifier                      = "${local.secondary_id}-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  engine                          = aws_rds_cluster.secondary.engine
  instance_class                  = var.instance_class
  availability_zone               = try(local.secondary_azs[count.index], null)
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  promotion_tier                  = count.index
  publicly_accessible             = false
  auto_minor_version_upgrade      = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
}
