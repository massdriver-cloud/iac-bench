###############################################################################
# Aurora instances.
#
# The primary cluster runs 2 by default (writer + in-region failover target).
# The DR cluster runs at least 1 — a warm standby that can be promoted
# immediately, which is what keeps the failover inside the minutes-scale RTO.
###############################################################################

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.instance_count

  identifier         = format("%s-primary-%02d", local.name, count.index + 1)
  cluster_identifier = aws_rds_cluster.primary.id
  engine             = local.engine
  instance_class     = var.instance_class

  # Minor versions move deliberately via var.engine_version so the two
  # members of the global database never drift apart.
  auto_minor_version_upgrade = false

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period

  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = false

  tags = {
    Name = format("%s-primary-%02d", local.name, count.index + 1)
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = format("%s-secondary-%02d", local.name, count.index + 1)
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = local.engine
  instance_class     = var.instance_class

  auto_minor_version_upgrade = false

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = aws_iam_role.rds_monitoring.arn

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period

  preferred_maintenance_window = var.preferred_maintenance_window
  apply_immediately            = false

  tags = {
    Name = format("%s-secondary-%02d", local.name, count.index + 1)
  }
}
