# ---------------------------------------------------------------------------
# Primary region: writable cluster
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  provider = aws

  cluster_identifier              = "${local.stack}-primary"
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  database_name                   = local.database_name
  port                            = var.port
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]

  # Credentials. Prefer the RDS-managed master password stored in Secrets
  # Manager; var.master_password is only for migrating existing databases.
  master_username             = var.master_username
  master_password             = var.master_password
  manage_master_user_password = var.master_password == null ? true : null

  # Encryption at rest (required for customer/payment data).
  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  # Backups: a global database is backed up from the primary region and
  # supports point-in-time recovery across the retention window.
  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window

  # Hardening and observability.
  iam_database_authentication_enabled = var.iam_database_auth_enabled
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true

  # Safety: never silently destroy a production database.
  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.stack}-primary-final"
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws

  count = var.instances_per_cluster

  identifier         = "${local.stack}-primary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine

  # Spread failover priority: instance 1 is the preferred writer, the others
  # take over in order during an AZ or instance failure.
  promotion_tier = count.index

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  publicly_accessible        = false
  copy_tags_to_snapshot      = true

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? aws_kms_key.primary.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
