# ---------------------------------------------------------------------------
# Secondary (DR) cluster in the second US region. It continuously receives
# storage-level replication from the primary (typically < 1s lag), serves
# local reads for the EKS workloads in this region, and becomes the writer
# after a global failover.
#
# Notes on global-database semantics:
#   * credentials, database name and cluster parameters are inherited from
#     the primary - they are intentionally NOT set here
#   * a region-local CMK is required for the encrypted secondary storage
#   * the cluster can only be created once the primary has an instance
#     (hence the explicit depends_on)
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = "${local.name}-secondary"
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  engine_mode               = "provisioned"
  global_cluster_identifier = aws_rds_global_cluster.this.id

  port = var.port

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  db_subnet_group_name   = aws_db_subnet_group.secondary.name
  vpc_security_group_ids = [aws_security_group.secondary.id]

  iam_database_authentication_enabled = true

  backup_retention_period      = 35
  preferred_backup_window      = "03:00-04:00"
  preferred_maintenance_window = "sun:05:00-sun:06:00"
  copy_tags_to_snapshot        = true

  deletion_protection       = true
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.name}-secondary-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  apply_immediately = var.apply_immediately

  tags = var.tags

  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.name}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name = aws_db_subnet_group.secondary.name
  promotion_tier       = count.index
  publicly_accessible  = false

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = var.performance_insights_retention_days

  monitoring_interval = 60
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  auto_minor_version_upgrade = true
  apply_immediately          = var.apply_immediately

  tags = var.tags
}
