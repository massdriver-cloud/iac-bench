locals {
  family    = "aurora-postgresql16"
  engine    = "aurora-postgresql"
  instances = { a = 0, b = 1 }
  cluster_parameters = {
    "rds.force_ssl"           = { value = "1", apply_method = "pending-reboot" }
    "log_statement"           = { value = "none", apply_method = "immediate" }
    "log_min_error_statement" = { value = "panic", apply_method = "immediate" }
  }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name}-pg16"
  family      = local.family
  description = "TLS and SQL logging defaults for ${local.name}"
  tags        = local.tags

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
  name        = "${local.name}-pg16"
  family      = local.family
  description = "TLS and SQL logging defaults for ${local.name}"
  tags        = local.tags

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
  global_cluster_identifier = local.name
  engine                    = local.engine
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
  tags                      = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name}-${var.regions.primary}"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = local.engine
  engine_version                      = var.engine_version
  port                                = local.port
  database_name                       = var.database_name
  master_username                     = local.admin
  master_password_wo                  = ephemeral.aws_secretsmanager_secret_version.bootstrap.secret_string
  master_password_wo_version          = 1
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn

  backup_retention_period               = 35
  preferred_backup_window               = "05:00-05:30"
  preferred_maintenance_window          = "sun:06:00-sun:06:30"
  copy_tags_to_snapshot                 = true
  deletion_protection                   = true
  skip_final_snapshot                   = false
  final_snapshot_identifier             = "${local.name}-${var.regions.primary}-final"
  apply_immediately                     = false
  auto_minor_version_upgrade            = false
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  database_insights_mode                = "standard"
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  tags                                  = local.tags

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    prevent_destroy = true
    # Upgrades use the global cluster; managed failovers can change the source.
    ignore_changes = [engine_version, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  for_each                   = local.instances
  identifier                 = "${aws_rds_cluster.primary.cluster_identifier}-${each.key}"
  cluster_identifier         = aws_rds_cluster.primary.id
  engine                     = aws_rds_cluster.primary.engine
  instance_class             = var.instance_class
  availability_zone          = try(local.primary_db_azs[each.value], null)
  promotion_tier             = each.value
  db_subnet_group_name       = aws_db_subnet_group.primary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
  apply_immediately          = false
  tags                       = local.tags
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name}-${var.regions.secondary}"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  source_region                       = var.regions.primary
  engine                              = local.engine
  engine_version                      = var.engine_version
  port                                = local.port
  iam_database_authentication_enabled = true
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  enable_global_write_forwarding      = false

  backup_retention_period               = 35
  preferred_backup_window               = "08:00-08:30"
  preferred_maintenance_window          = "sun:09:00-sun:09:30"
  copy_tags_to_snapshot                 = true
  deletion_protection                   = true
  skip_final_snapshot                   = false
  final_snapshot_identifier             = "${local.name}-${var.regions.secondary}-final"
  apply_immediately                     = false
  auto_minor_version_upgrade            = false
  enabled_cloudwatch_logs_exports       = ["postgresql"]
  database_insights_mode                = "standard"
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  tags                                  = local.tags

  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [engine_version, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                   = aws.secondary
  for_each                   = local.instances
  identifier                 = "${aws_rds_cluster.secondary.cluster_identifier}-${each.key}"
  cluster_identifier         = aws_rds_cluster.secondary.id
  engine                     = aws_rds_cluster.secondary.engine
  instance_class             = var.instance_class
  availability_zone          = try(local.secondary_db_azs[each.value], null)
  promotion_tier             = each.value
  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
  apply_immediately          = false
  tags                       = local.tags
}
