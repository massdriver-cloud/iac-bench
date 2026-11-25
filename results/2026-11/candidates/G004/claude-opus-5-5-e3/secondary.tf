# ---------------------------------------------------------------------------
# Secondary region: read-only replica cluster, promotable on regional failure
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = local.secondary_cluster_id
  description = "Database subnets for ${local.name}"
  subnet_ids  = data.aws_subnets.secondary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary.ids) >= 2
      error_message = "At least two subnets tagged tier=database are required in the secondary VPC."
    }
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.secondary_cluster_id}-aurora"
  description = "Aurora PostgreSQL ${local.name}"
  vpc_id      = data.aws_vpc.secondary.id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = length(var.secondary_allowed_security_group_ids) == 0 ? toset([for a in data.aws_vpc.secondary.cidr_block_associations : a.cidr_block]) : toset([])

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${local.vpc_name} VPC"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.name}-"
  family      = local.family
  description = "Aurora PostgreSQL ${local.name} cluster parameters"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier        = local.secondary_cluster_id
  global_cluster_identifier = aws_rds_global_cluster.this.id
  engine                    = aws_rds_global_cluster.this.engine
  engine_version            = aws_rds_global_cluster.this.engine_version
  port                      = local.port

  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name

  storage_encrypted                   = true
  kms_key_id                          = aws_kms_key.secondary.arn
  iam_database_authentication_enabled = true

  backup_retention_period      = var.backup_retention_days
  preferred_backup_window      = var.preferred_backup_window
  preferred_maintenance_window = var.preferred_maintenance_window
  copy_tags_to_snapshot        = true
  deletion_protection          = var.deletion_protection
  skip_final_snapshot          = false
  final_snapshot_identifier    = "${local.secondary_cluster_id}-final"

  enabled_cloudwatch_logs_exports = ["postgresql"]

  # The secondary can only join once the primary has a writer instance.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]

  lifecycle {
    ignore_changes = [replication_source_identifier, global_cluster_identifier]
  }
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier         = "${local.secondary_cluster_id}-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.secondary.id
  engine             = aws_rds_cluster.secondary.engine
  engine_version     = aws_rds_cluster.secondary.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name       = aws_db_subnet_group.secondary.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
  ca_cert_identifier         = "rds-ca-rsa2048-g1"
  promotion_tier             = count.index == 0 ? 0 : 1

  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  monitoring_interval                   = 30
  monitoring_role_arn                   = aws_iam_role.monitoring.arn

  depends_on = [aws_iam_role_policy_attachment.monitoring]
}

# Replication lag is the effective RPO of a regional failover.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag"
  alarm_description   = "Aurora global replication lag for ${local.name} exceeds RPO budget."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }
  alarm_actions = lookup(var.alarm_sns_topic_arns, var.secondary_region, [])
  ok_actions    = lookup(var.alarm_sns_topic_arns, var.secondary_region, [])
}
