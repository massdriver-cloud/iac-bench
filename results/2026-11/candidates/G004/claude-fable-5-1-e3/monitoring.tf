# Alarms that matter for the recovery objectives. Notification targets are
# optional; the alarms still show up in the console and can be wired up later.

# Cross-region replication lag is the thing that turns a regional failover
# into lost writes. The metric is emitted by the secondary cluster.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name}-aurora-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag for ${local.name} is above ${var.replication_lag_alarm_threshold_ms}ms; the enforced RPO (${var.rpo_seconds}s) is at risk."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.alarm_actions.secondary
  ok_actions    = var.alarm_actions.secondary
}

# Writer running out of headroom in the primary region.
resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  alarm_name          = "${local.name}-aurora-primary-cpu"
  alarm_description   = "Aurora ${local.name} primary cluster CPU above 85% for 15 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    Role                = "WRITER"
  }

  alarm_actions = var.alarm_actions.primary
  ok_actions    = var.alarm_actions.primary
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  alarm_name          = "${local.name}-aurora-primary-freeable-memory"
  alarm_description   = "Aurora ${local.name} primary writer has under 512 MiB freeable memory."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 536870912
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    Role                = "WRITER"
  }

  alarm_actions = var.alarm_actions.primary
  ok_actions    = var.alarm_actions.primary
}
