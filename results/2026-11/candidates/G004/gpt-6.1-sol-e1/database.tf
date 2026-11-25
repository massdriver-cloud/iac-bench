resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = true
  lifecycle { prevent_destroy = true }
}
resource "aws_db_subnet_group" "primary" {
  name       = "${local.prefix}-db"
  subnet_ids = values(var.primary_network.database_subnets)
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.prefix}-db"
  subnet_ids = values(var.secondary_network.database_subnets)
}
locals {
  # Do not log statements or bind values containing customer/payment data.
  cluster_parameters = {
    "rds.force_ssl"                     = "1"
    "password_encryption"               = "scram-sha-256"
    "log_connections"                   = "1"
    "log_disconnections"                = "1"
    "log_lock_waits"                    = "1"
    "log_statement"                     = "none"
    "log_min_duration_statement"        = "-1"
    "log_min_error_statement"           = "panic"
    "log_parameter_max_length"          = "0"
    "log_parameter_max_length_on_error" = "0"
    # AWS's smallest supported managed RPO is 20s, NOT a few-second guarantee.
    # It blocks primary commits when global replication falls behind.
    "rds.global_db_rpo" = "20"
  }
}
resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.prefix}-pg16-"
  family      = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-pg16-"
  family      = "aurora-postgresql16"
  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value
      apply_method = "pending-reboot"
    }
  }
  lifecycle { create_before_destroy = true }
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.prefix}-primary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.primary.arn
  skip_destroy      = true
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.prefix}-secondary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.secondary.arn
  skip_destroy      = true
}
resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.prefix}-primary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  database_name                       = aws_rds_global_cluster.this.database_name
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  master_username                     = "dbadmin"
  master_password                     = random_password.admin.result
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.primary.arn
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "05:00-06:00"
  preferred_maintenance_window        = "sun:07:00-sun:08:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-primary-final"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  depends_on                          = [aws_cloudwatch_log_group.primary]
  lifecycle { prevent_destroy = true }
}
resource "aws_rds_cluster_instance" "primary" {
  count                                 = 2
  identifier                            = "${local.prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = sort(keys(var.primary_network.database_subnets))[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = false
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  apply_immediately                     = false
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
  lifecycle { prevent_destroy = true }
}
resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.prefix}-secondary"
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = var.engine_version
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  source_region                       = var.primary_region
  port                                = 5432
  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = 35
  preferred_backup_window             = "06:00-07:00"
  preferred_maintenance_window        = "sun:08:00-sun:09:00"
  copy_tags_to_snapshot               = true
  deletion_protection                 = true
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.prefix}-secondary-final"
  apply_immediately                   = false
  allow_major_version_upgrade         = false
  # The first global member becomes writer: wait for the actual primary instance.
  depends_on = [aws_rds_cluster_instance.primary, aws_cloudwatch_log_group.secondary]
  lifecycle { prevent_destroy = true }
}
resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = 2
  identifier                            = "${local.prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  availability_zone                     = sort(keys(var.secondary_network.database_subnets))[count.index]
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = false
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true
  apply_immediately                     = false
  depends_on                            = [aws_iam_role_policy_attachment.monitoring]
  lifecycle { prevent_destroy = true }
}
