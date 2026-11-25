############################################
# CloudWatch alarms
#
# The replication-lag alarm is the one that matters for the business RPO: lag is
# exactly how many seconds of writes an unplanned regional failover would lose.
############################################

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag into ${var.secondary_region} exceeds ${var.replication_lag_alarm_threshold_ms} ms (RPO at risk)"
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

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Average CPU across ${local.primary_cluster_id} above 80% for 15 minutes"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.alarm_actions.primary
  ok_actions    = var.alarm_actions.primary
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-memory-low"
  alarm_description   = "Freeable memory on ${local.primary_cluster_id} below 1 GiB"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1073741824
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.alarm_actions.primary
  ok_actions    = var.alarm_actions.primary
}

resource "aws_cloudwatch_metric_alarm" "primary_connections" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-connections-high"
  alarm_description   = "Database connections on ${local.primary_cluster_id} unusually high; check pooling before max_connections is hit"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.alarm_actions.primary
  ok_actions    = var.alarm_actions.primary
}
