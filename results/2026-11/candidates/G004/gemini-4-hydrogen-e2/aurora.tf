resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name_prefix}-primary/postgresql"
  retention_in_days = local.log_retention_in_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.name_prefix}-primary-postgresql-logs"
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.name_prefix}-secondary/postgresql"
  retention_in_days = local.log_retention_in_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.name_prefix}-secondary-postgresql-logs"
  }
}

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
  force_destroy             = false

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must be distinct US AWS regions for cross-region disaster recovery."
    }
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name_prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name             = aws_db_subnet_group.primary.name
  vpc_security_group_ids           = [aws_security_group.primary.id]
  db_cluster_parameter_group_name  = aws_rds_cluster_parameter_group.primary.name
  db_instance_parameter_group_name = aws_db_parameter_group.primary.name

  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-primary-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  apply_immediately               = var.apply_immediately
  allow_major_version_upgrade     = false

  depends_on = [aws_cloudwatch_log_group.primary]

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
    ]
  }

  tags = {
    Name = "${local.name_prefix}-primary"
    Role = "primary"
  }
}

resource "aws_rds_cluster_instance" "primary" {
  count = local.primary_instance_count

  identifier         = "${local.name_prefix}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version

  db_subnet_group_name       = aws_db_subnet_group.primary.name
  db_parameter_group_name    = aws_db_parameter_group.primary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = local.performance_insights_retention_days

  ca_cert_identifier = "rds-ca-rsa2048-g1"
  promotion_tier     = count.index
  apply_immediately  = var.apply_immediately

  tags = {
    Name = "${local.name_prefix}-primary-${count.index + 1}"
    Role = count.index == 0 ? "writer-preferred" : "reader"
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier                  = "${local.name_prefix}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.this.id
  engine                              = aws_rds_global_cluster.this.engine
  engine_version                      = aws_rds_global_cluster.this.engine_version
  iam_database_authentication_enabled = true

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name             = aws_db_subnet_group.secondary.name
  vpc_security_group_ids           = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name  = aws_rds_cluster_parameter_group.secondary.name
  db_instance_parameter_group_name = aws_db_parameter_group.secondary.name

  backup_retention_period      = local.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = var.skip_final_snapshot
  final_snapshot_identifier    = var.skip_final_snapshot ? null : "${local.name_prefix}-secondary-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]
  enable_global_write_forwarding  = var.enable_global_write_forwarding
  apply_immediately               = var.apply_immediately
  allow_major_version_upgrade     = false

  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [
      replication_source_identifier,
    ]
  }

  tags = {
    Name = "${local.name_prefix}-secondary"
    Role = "secondary"
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = local.secondary_instance_count

  identifier         = "${local.name_prefix}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version

  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  db_parameter_group_name    = aws_db_parameter_group.secondary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = true

  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.rds_enhanced_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = local.performance_insights_retention_days

  ca_cert_identifier = "rds-ca-rsa2048-g1"
  promotion_tier     = count.index
  apply_immediately  = var.apply_immediately

  tags = {
    Name = "${local.name_prefix}-secondary-${count.index + 1}"
    Role = "standby-reader"
  }
}
