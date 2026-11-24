resource "aws_rds_global_cluster" "main" {
  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection

  tags = local.common_tags
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${var.name}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.main.id
  engine                              = aws_rds_global_cluster.main.engine
  engine_version                      = aws_rds_global_cluster.main.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = local.primary_kms_key_arn
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = local.primary_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection

  skip_final_snapshot       = var.skip_final_snapshot
  final_snapshot_identifier = var.skip_final_snapshot ? null : "${var.name}-primary-final-snapshot"

  tags = merge(
    local.primary_tags,
    {
      Name = "${var.name}-primary"
      Role = "primary"
    }
  )

  depends_on = [
    aws_cloudwatch_log_group.primary_postgresql
  ]
}

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${var.name}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.main.id
  engine                              = aws_rds_global_cluster.main.engine
  engine_version                      = aws_rds_global_cluster.main.engine_version
  iam_database_authentication_enabled = true
  storage_encrypted                   = true
  kms_key_id                          = local.secondary_kms_key_arn

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]

  preferred_maintenance_window = var.preferred_maintenance_window

  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection

  skip_final_snapshot = true

  tags = merge(
    local.secondary_tags,
    {
      Name = "${var.name}-secondary"
      Role = "secondary"
    }
  )

  depends_on = [
    aws_rds_cluster.primary,
    aws_cloudwatch_log_group.secondary_postgresql
  ]
}

resource "aws_rds_cluster_instance" "primary" {
  count                      = var.primary_instance_count
  identifier                 = "${var.name}-primary-${count.index + 1}"
  cluster_identifier         = aws_rds_cluster.primary.id
  instance_class             = var.instance_class
  engine                     = aws_rds_cluster.primary.engine
  engine_version             = aws_rds_cluster.primary.engine_version
  db_subnet_group_name       = aws_db_subnet_group.primary.name
  db_parameter_group_name    = aws_db_parameter_group.primary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.primary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(
    local.primary_tags,
    {
      Name = "${var.name}-primary-${count.index + 1}"
      Role = count.index == 0 ? "writer" : "reader"
    }
  )
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                   = aws.secondary
  count                      = var.secondary_instance_count
  identifier                 = "${var.name}-secondary-${count.index + 1}"
  cluster_identifier         = aws_rds_cluster.secondary.id
  instance_class             = local.secondary_instance_class
  engine                     = aws_rds_cluster.secondary.engine
  engine_version             = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  db_parameter_group_name    = aws_db_parameter_group.secondary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = local.secondary_kms_key_arn
  performance_insights_retention_period = var.performance_insights_retention_period

  tags = merge(
    local.secondary_tags,
    {
      Name = "${var.name}-secondary-${count.index + 1}"
      Role = "reader"
    }
  )
}
