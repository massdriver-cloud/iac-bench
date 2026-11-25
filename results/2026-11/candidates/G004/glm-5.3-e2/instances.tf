# Cluster instances (Aurora compute). Instances are spread across the
# discovered database subnets, so prod defaults (2 instances per region) give
# each cluster an AZ-redundant writer + reader pair.

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = local.instance_count

  identifier          = "${local.name}-${var.primary_region}-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.primary.id
  engine              = local.engine
  engine_version      = local.engine_version
  instance_class      = var.instance_class
  publicly_accessible = false

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.primary.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  tags = {
    Name = "${local.name}-${var.primary_region}-${count.index + 1}"
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = local.secondary_instance_count

  identifier          = "${local.name}-${var.secondary_region}-${count.index + 1}"
  cluster_identifier  = aws_rds_cluster.secondary.id
  engine              = local.engine
  engine_version      = local.engine_version
  instance_class      = var.instance_class
  publicly_accessible = false

  performance_insights_enabled          = var.performance_insights_enabled
  performance_insights_retention_period = var.performance_insights_retention_period
  performance_insights_kms_key_id       = var.performance_insights_enabled ? aws_kms_key.secondary.arn : null

  monitoring_interval = var.monitoring_interval
  monitoring_role_arn = var.monitoring_interval > 0 ? aws_iam_role.rds_enhanced_monitoring[0].arn : null

  tags = {
    Name = "${local.name}-${var.secondary_region}-${count.index + 1}"
  }
}
