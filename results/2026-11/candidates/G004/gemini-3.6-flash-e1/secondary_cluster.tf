resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name_prefix}-secondary"
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version

  db_subnet_group_name                = aws_db_subnet_group.secondary.name
  vpc_security_group_ids              = [aws_security_group.secondary.id]
  storage_encrypted                   = true
  kms_key_id                          = local.secondary_kms_key_arn
  iam_database_authentication_enabled = true
  db_cluster_parameter_group_name     = aws_rds_cluster_parameter_group.secondary.name

  preferred_maintenance_window    = var.preferred_maintenance_window
  enabled_cloudwatch_logs_exports = ["postgresql"]
  copy_tags_to_snapshot           = true
  deletion_protection             = var.deletion_protection
  skip_final_snapshot             = var.skip_final_snapshot
  final_snapshot_identifier       = var.skip_final_snapshot ? null : "${local.name_prefix}-secondary-final-snapshot"

  tags = local.common_tags

  depends_on = [
    aws_rds_cluster_instance.primary
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  count    = var.secondary_instance_count
  provider = aws.secondary

  identifier                   = "${local.name_prefix}-secondary-${count.index + 1}"
  cluster_identifier           = aws_rds_cluster.secondary.id
  engine                       = "aurora-postgresql"
  engine_version               = var.engine_version
  instance_class               = var.instance_class
  db_subnet_group_name         = aws_db_subnet_group.secondary.name
  publicly_accessible          = false
  auto_minor_version_upgrade   = true
  preferred_maintenance_window = var.preferred_maintenance_window

  tags = local.common_tags
}
