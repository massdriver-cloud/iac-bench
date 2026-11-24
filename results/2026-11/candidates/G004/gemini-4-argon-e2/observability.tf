# ------------------------------------------------------------------------------
# CloudWatch Log Groups for Aurora PostgreSQL Audit & IAM Auth Logs
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary" {
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name    = "${local.primary_cluster_id}-${each.value}-logs"
    LogType = each.value
    Region  = var.primary_region
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary
  for_each = toset(local.cloudwatch_log_exports)

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name    = "${local.secondary_cluster_id}-${each.value}-logs"
    LogType = each.value
    Region  = var.secondary_region
  }
}

# ------------------------------------------------------------------------------
# CloudWatch Metric Alarms (RPO Replication Lag & Regional Cluster Health)
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag-high"
  alarm_description   = "Aurora Global Database cross-region replication lag for ${var.service_name} (${local.env_short}) exceeded ${var.rpo_max_replication_lag_ms}ms RPO threshold"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.rpo_max_replication_lag_ms
  treat_missing_data  = "breaching"
  alarm_actions       = var.alarm_actions_secondary
  ok_actions          = var.alarm_actions_secondary

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-global-replication-lag-high"
    Region = var.secondary_region
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  alarm_name          = "${local.primary_cluster_id}-cpu-utilization-high"
  alarm_description   = "Aurora PostgreSQL primary cluster CPU utilization > 80% for ${var.service_name} (${local.env_short})"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions_primary
  ok_actions          = var.alarm_actions_primary

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  tags = {
    Name   = "${local.primary_cluster_id}-cpu-utilization-high"
    Region = var.primary_region
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  alarm_name          = "${local.primary_cluster_id}-freeable-memory-low"
  alarm_description   = "Aurora PostgreSQL primary cluster freeable memory < 512MB for ${var.service_name} (${local.env_short})"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Minimum"
  threshold           = 536870912
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions_primary
  ok_actions          = var.alarm_actions_primary

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  tags = {
    Name   = "${local.primary_cluster_id}-freeable-memory-low"
    Region = var.primary_region
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-cpu-utilization-high"
  alarm_description   = "Aurora PostgreSQL secondary cluster CPU utilization > 80% for ${var.service_name} (${local.env_short})"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions_secondary
  ok_actions          = var.alarm_actions_secondary

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-cpu-utilization-high"
    Region = var.secondary_region
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory_low" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-freeable-memory-low"
  alarm_description   = "Aurora PostgreSQL secondary cluster freeable memory < 512MB for ${var.service_name} (${local.env_short})"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Minimum"
  threshold           = 536870912
  treat_missing_data  = "notBreaching"
  alarm_actions       = var.alarm_actions_secondary
  ok_actions          = var.alarm_actions_secondary

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  tags = {
    Name   = "${local.secondary_cluster_id}-freeable-memory-low"
    Region = var.secondary_region
  }
}
