# ---------------------------------------------------------------------------
# Secondary region: read-only replica cluster
#
# The secondary cluster receives replicated writes from the primary via the
# global cluster; it takes no master credentials and no backup configuration
# (Aurora manages global-database backups from the primary region). It keeps
# its own instances so that, on promotion, the service is immediately able to
# serve reads and writes from this region.
# ---------------------------------------------------------------------------

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier              = "${local.stack}-secondary"
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = aws_rds_global_cluster.this.engine
  engine_version                  = aws_rds_global_cluster.this.engine_version
  port                            = var.port
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]

  storage_encrypted = true
  kms_key_id        = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = var.iam_database_auth_enabled
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true

  deletion_protection       = var.deletion_protection
  skip_final_snapshot       = false
  final_snapshot_identifier = "${local.stack}-secondary-final"

  # The secondary can only join the global cluster once the primary cluster
  # (and its instances) exist.
  depends_on = [aws_rds_cluster_instance.primary]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary

  count = var.instances_per_cluster

  identifier         = "${local.stack}-secondary-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  instance_class     = var.instance_class
  engine             = aws_rds_cluster.secondary.engine

  promotion_tier = count.index

  auto_minor_version_upgrade = var.auto_minor_version_upgrade
  publicly_accessible        = false
  copy_tags_to_snapshot      = true

  performance_insights_enabled    = var.performance_insights_enabled
  performance_insights_kms_key_id = var.performance_insights_enabled ? aws_kms_key.secondary.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null

  depends_on = [aws_iam_role_policy_attachment.rds_monitoring]
}
