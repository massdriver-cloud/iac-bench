locals {
  family = "aurora-postgresql${split(".", var.engine_version)[0]}"
  parameters = {
    "rds.force_ssl"            = { value = "1", apply_method = "immediate" }
    "shared_preload_libraries" = { value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" }
    "pgaudit.log"              = { value = "ddl,role", apply_method = "immediate" }
    "log_connections"          = { value = "1", apply_method = "immediate" }
    "log_disconnections"       = { value = "1", apply_method = "immediate" }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora ${var.name} storage (primary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora ${var.name} storage (secondary region)"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name   = "${var.name}-primary"
  family = local.family
  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary
  name     = "${var.name}-secondary"
  family   = local.family
  dynamic "parameter" {
    for_each = local.parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

ephemeral "random_password" "master" {
  length  = 32
  special = false
}

# Resolving the version fails the plan when AWS does not offer it.
data "aws_rds_engine_version" "this" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = var.name
  engine                    = "aurora-postgresql"
  engine_version            = data.aws_rds_engine_version.this.version
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  master_username                     = "postgres_admin"
  master_password_wo                  = ephemeral.random_password.master.result
  master_password_wo_version          = 1
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  backup_retention_period             = var.backup_retention_days
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.name}-primary-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  lifecycle {
    ignore_changes = [engine_version]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  backup_retention_period             = var.backup_retention_days
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = "${var.name}-secondary-final"
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  lifecycle {
    ignore_changes = [engine_version]
  }

  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_iam_role" "monitoring" {
  name_prefix = "${var.name}-rds-mon-"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_rds_cluster_instance" "primary" {
  count                           = var.instances_per_region
  identifier                      = "${var.name}-primary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.primary.id
  engine                          = aws_rds_cluster.primary.engine
  instance_class                  = var.instance_class
  publicly_accessible             = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.primary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                        = aws.secondary
  count                           = var.instances_per_region
  identifier                      = "${var.name}-secondary-${count.index + 1}"
  cluster_identifier              = aws_rds_cluster.secondary.id
  engine                          = aws_rds_cluster.secondary.engine
  instance_class                  = var.instance_class
  publicly_accessible             = false
  performance_insights_enabled    = true
  performance_insights_kms_key_id = aws_kms_key.secondary.arn
  monitoring_interval             = 60
  monitoring_role_arn             = aws_iam_role.monitoring.arn
}
