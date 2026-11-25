# ---------------------------------------------------------------------------
# SECONDARY (DR) cluster in the failover region.
#
# This is a hot standby: same engine version, same instance class and the
# same instance count as the primary so the region can absorb full
# production traffic the moment it is promoted. It joins the global
# database, receives storage-level replication from the primary cluster,
# and keeps its own automated backups.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.dr

  cluster_identifier = local.secondary_cluster_id
  engine             = "aurora-postgresql"
  engine_version     = var.engine_version

  global_cluster_identifier = aws_rds_global_cluster.this.id

  # The global database can only accept a secondary member once the primary
  # cluster exists and has instances running.
  depends_on = [aws_rds_cluster_instance.primary]

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  port                            = local.postgres_port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.secondary_cluster_id}-final"

  tags = {
    Name = local.secondary_cluster_id
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.dr
  count    = var.instance_count

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  promotion_tier     = count.index

  auto_minor_version_upgrade = true
  publicly_accessible        = false
  copy_tags_to_snapshot      = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${local.secondary_cluster_id}-${count.index + 1}"
  }
}
