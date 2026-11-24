# ---------------------------------------------------------------------------
# Aurora Global Database: one logical database spanning two US regions.
# Storage-level physical replication gives an RPO of ~1 second and an RTO of
# ~1 minute for cross-region failover (managed switchover for planned events,
# detach-and-promote for a regional outage). This is what meets the business
# bar of "serving from another region within minutes, losing at most a few
# seconds of writes".
# ---------------------------------------------------------------------------

resource "aws_rds_global_cluster" "this" {
  global_cluster_identifier = local.name
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  storage_encrypted         = true
  deletion_protection       = true
}

# ---------------------------------------------------------------------------
# Primary cluster (writer + in-region readers). Production guardrails are
# fixed by the module, not left to callers:
#   * CMK encryption at rest, TLS enforced in transit (parameter group)
#   * master password generated & managed by RDS in Secrets Manager (no
#     password ever passes through variables, state inputs or CI logs)
#   * 35-day automated backups (point-in-time recovery), tagged snapshots
#   * deletion protection + mandatory final snapshot
#   * IAM database authentication for EKS workload roles
#   * PostgreSQL logs (incl. pgaudit) exported to CloudWatch
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "primary" {
  cluster_identifier        = local.name
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  database_name   = local.database_name
  port            = var.port
  master_username = var.master_username

  manage_master_user_password   = true
  master_user_secret_kms_key_id = aws_kms_key.primary.arn

  storage_encrypted = true
  kms_key_id        = aws_kms_key.primary.arn

  db_subnet_group_name            = aws_db_subnet_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name

  iam_database_authentication_enabled = true

  backup_retention_period      = 35
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately = var.apply_immediately

  tags = var.tags

  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "primary_region and secondary_region must differ: the DR cluster has to survive a full regional outage."
    }
  }
}

# Writer (promotion tier 0) plus readers. Multi-AZ placement is handled by the
# subnet group; an instance/AZ failure promotes a reader automatically in
# ~30 seconds without touching the DR region.
resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier         = "${local.name}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = aws_rds_cluster.primary.engine
  engine_version     = aws_rds_cluster.primary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.primary.name
  promotion_tier       = count.index
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  tags = var.tags
}
