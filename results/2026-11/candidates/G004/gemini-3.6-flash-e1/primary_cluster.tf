resource "aws_rds_cluster" "primary" {
  provider = aws

  cluster_identifier        = "${local.name_prefix}-primary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  master_username           = var.master_username
  master_password           = var.master_password
  database_name             = local.database_name

  db_subnet_group_name                = aws_db_subnet_group.primary.name
  vpc_security_group_ids              = [aws_security_group.primary.id]
  storage_encrypted                   = true
  kms_key_id                          = local.primary_kms_key_arn
  iam_database_authentication_enabled = true
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.primary.name

  backup_retention_period         = var.backup_retention_period
  preferred_backup_window         = var.preferred_backup_window
  preferred_maintenance_window    = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${local.name_prefix}-primary-final-snapshot"

  tags = local.common_tags

  depends_on = [aws_rds_global_cluster.this]
}

resource "aws_rds_cluster_instance" "primary" {
  count    = var.primary_instance_count
  provider = aws

  identifier                   = "${local.name_prefix}-primary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.primary.id
  engine                       = "aurora-postgresql"
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.primary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window

  tags = local.common_tags
}
