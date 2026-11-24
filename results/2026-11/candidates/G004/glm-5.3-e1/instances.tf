# ---------------------------------------------------------------------------
# DB instances
# ---------------------------------------------------------------------------

# One instance is the writer (Aurora PostgreSQL allows exactly one writer per
# cluster); any further instances are readers that add availability and read
# capacity within the primary region.
resource "aws_rds_cluster_instance" "primary" {
  count = local.primary_instance_count

  identifier         = "${local.name}-${count.index}"
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = local.engine
  instance_class     = local.instance_class

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = local.monitoring_role_arn
}

# Warm-standby instances in the second region. They serve reads locally today
# and become the writer(s) after a regional failover.
resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = local.secondary_instance_count

  identifier         = "${local.name}-${var.secondary_region}-${count.index}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = local.engine
  instance_class     = local.instance_class

  publicly_accessible        = false
  auto_minor_version_upgrade = var.auto_minor_version_upgrade

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_enabled ? var.performance_insights_retention_period : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = local.monitoring_role_arn
}
