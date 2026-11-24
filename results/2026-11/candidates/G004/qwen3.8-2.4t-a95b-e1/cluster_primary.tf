# ---------------------------------------------------------------------------
# Aurora global database + PRIMARY cluster
#
# DR posture:
#   * Global database replicates the cluster's storage to the secondary
#     region at storage level, typically < 1 second behind, so a regional
#     failover loses at most a few seconds of writes.
#   * instance_count >= 2 instances spread across AZs keep the database up
#     through any single-AZ failure without leaving the region.
#   * Failover itself is an operator action (see the failover_command
#     output) — promotion completes in about a minute.
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.global_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true

  tags = {
    Name = local.global_cluster_id
  }
}

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.primary_cluster_id
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  global_cluster_identifier = aws_rds_global_cluster.this.id

  database_name   = local.database_name
  master_username = var.master_username
  # Password lives in Secrets Manager (managed by RDS), never in config or
  # plaintext state. EKS workloads use IAM authentication instead.
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  port                            = local.postgres_port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_period
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true

  enabled_cloudwatch_logs_exports = ["postgresql"]

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.primary_cluster_id}-final"

  tags = {
    Name = local.primary_cluster_id
  }
}

# One writer + readers, spread across AZs by Aurora automatically.
# Instance index 0 gets promotion tier 0 (stays writer), readers rank
# behind it in any in-region failover.
resource "aws_rds_cluster_instance" "primary" {
  count = var.instance_count

  identifier         = "${local.primary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  promotion_tier     = count.index

  auto_minor_version_upgrade = true
  publicly_accessible        = false
  copy_tags_to_snapshot      = true

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.enhanced_monitoring.arn

  performance_insights_enabled          = true
  performance_insights_retention_period = 7

  tags = {
    Name = "${local.primary_cluster_id}-${count.index + 1}"
  }
}
