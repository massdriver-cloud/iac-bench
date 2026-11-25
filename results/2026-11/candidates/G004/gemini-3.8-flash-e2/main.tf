# Aurora PostgreSQL Global Database Architecture
# Multi-Region replication delivers RPO < a few seconds and RTO < minutes

resource "aws_rds_global_cluster" "global" {
  global_cluster_identifier = "${local.name_prefix}-global"
  engine                    = "aurora-postgresql"
  engine_version            = local.engine_version
  database_name             = local.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

# Primary Region Cluster (Writer & Readers)

resource "aws_rds_cluster" "primary" {
  cluster_identifier                  = "${local.name_prefix}-primary"
  global_cluster_identifier           = aws_rds_global_cluster.global.id
  engine                              = aws_rds_global_cluster.global.engine
  engine_version                      = aws_rds_global_cluster.global.engine_version
  database_name                       = local.database_name
  master_username                     = var.master_username
  manage_master_user_password         = true
  master_user_secret_kms_key_id       = aws_kms_key.primary.arn
  kms_key_id                          = aws_kms_key.primary.arn
  storage_encrypted                   = true
  db_subnet_group_name                = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  iam_database_authentication_enabled = true
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.name_prefix}-primary-final-snapshot"
  enabled_cloudwatch_logs_exports     = ["postgresql"]
}

resource "aws_rds_cluster_instance" "primary" {
  count                                 = var.primary_instance_count
  identifier                            = "${local.name_prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  instance_class                        = var.instance_class
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  copy_tags_to_snapshot                 = true
}

# Secondary Region Cluster (Read Replica & DR promotion target)

resource "aws_rds_cluster" "secondary" {
  provider                            = aws.secondary
  cluster_identifier                  = "${local.name_prefix}-secondary"
  global_cluster_identifier           = aws_rds_global_cluster.global.id
  engine                              = aws_rds_global_cluster.global.engine
  engine_version                      = aws_rds_global_cluster.global.engine_version
  kms_key_id                          = aws_kms_key.secondary.arn
  storage_encrypted                   = true
  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  iam_database_authentication_enabled = true
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = var.skip_final_snapshot
  final_snapshot_identifier           = var.skip_final_snapshot ? null : "${local.name_prefix}-secondary-final-snapshot"
  enabled_cloudwatch_logs_exports     = ["postgresql"]

  # Secondary cluster requires primary cluster instance to be fully ready
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider                              = aws.secondary
  count                                 = var.secondary_instance_count
  identifier                            = "${local.name_prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  instance_class                        = var.instance_class
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = true
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_period
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  copy_tags_to_snapshot                 = true
}
