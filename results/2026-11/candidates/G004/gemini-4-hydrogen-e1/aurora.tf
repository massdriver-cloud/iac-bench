resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name_prefix}-primary/postgresql"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.name_prefix}-secondary/postgresql"
  retention_in_days = local.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_cluster_instance" "primary" {
  count = var.primary_instance_count

  identifier                            = "${local.name_prefix}-primary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = aws_rds_cluster.primary.engine
  engine_version                        = aws_rds_cluster.primary.engine_version
  instance_class                        = local.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  db_parameter_group_name               = aws_db_parameter_group.primary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = local.performance_insights_retention_days
  apply_immediately                     = local.apply_immediately
  promotion_tier                        = count.index
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                            = "${local.name_prefix}-secondary-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = aws_rds_cluster.secondary.engine
  engine_version                        = aws_rds_cluster.secondary.engine_version
  instance_class                        = local.secondary_instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  db_parameter_group_name               = aws_db_parameter_group.secondary.name
  publicly_accessible                   = false
  auto_minor_version_upgrade            = var.auto_minor_version_upgrade
  ca_cert_identifier                    = "rds-ca-rsa2048-g1"
  monitoring_interval                   = var.monitoring_interval
  monitoring_role_arn                   = var.monitoring_interval > 0 ? aws_iam_role.rds_monitoring.arn : null
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = local.performance_insights_retention_days
  apply_immediately                     = local.apply_immediately
  promotion_tier                        = count.index
}
