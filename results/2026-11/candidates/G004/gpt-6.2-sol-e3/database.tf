data "aws_rds_orderable_db_instance" "primary" {
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  instance_class            = var.instance_class
  supports_global_databases = true
  storage_type              = "aurora"
}

data "aws_rds_orderable_db_instance" "secondary" {
  provider                  = aws.secondary
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  instance_class            = var.instance_class
  supports_global_databases = true
  storage_type              = "aurora"
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = true
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name   = local.name
  family = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.postgresql_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary
  name     = local.name
  family   = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.postgresql_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
}

locals {
  postgresql_parameters = {
    "rds.force_ssl"         = "1"
    log_connections         = "1"
    log_disconnections      = "1"
    log_min_error_statement = "panic"
  }
}

resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name}-primary/postgresql"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name}-secondary/postgresql"
  retention_in_days = 90
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  engine_mode                         = "provisioned"
  engine_lifecycle_support            = "open-source-rds-extended-support-disabled"
  database_name                       = local.database_name
  master_username                     = local.admin_user
  master_password_wo                  = jsondecode(ephemeral.aws_secretsmanager_secret_version.admin.secret_string).password
  master_password_wo_version          = var.admin_credential_version
  port                                = local.port
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "03:00-04:00"
  preferred_maintenance_window        = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-primary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false

  depends_on = [aws_cloudwatch_log_group.primary]
  lifecycle {
    # The global resource coordinates minor upgrades across both regional members.
    ignore_changes = [engine_version, replication_source_identifier]
  }
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  engine_mode                         = "provisioned"
  engine_lifecycle_support            = "open-source-rds-extended-support-disabled"
  source_region                       = var.primary_region
  port                                = local.port
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "04:00-05:00"
  preferred_maintenance_window        = "sun:06:00-sun:07:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.name}-secondary-final-${random_id.snapshot.hex}"
  apply_immediately                   = false

  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
  lifecycle {
    ignore_changes = [engine_version, replication_source_identifier]
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = 2
  identifier                            = "${local.name}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  instance_class                        = data.aws_rds_orderable_db_instance.primary.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  availability_zone                     = try(local.primary_azs[count.index], null)
  promotion_tier                        = count.index
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = 2
  identifier                            = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  instance_class                        = data.aws_rds_orderable_db_instance.secondary.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  availability_zone                     = try(local.secondary_azs[count.index], null)
  promotion_tier                        = count.index
  publicly_accessible                   = false
  auto_minor_version_upgrade            = false
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
}
