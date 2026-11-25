# Cross-region replication lag is the data-loss exposure: whatever the standby
# has not received yet is what a regional failover would lose. Alarm when it
# stops being "a few seconds".
#
# The metric is only published for the cluster that is currently the standby,
# so there is one alarm per region and whichever is the standby at the time is
# the live one; the alarm on the current writer has no data and stays quiet.

resource "aws_cloudwatch_metric_alarm" "replication_lag_primary" {
  alarm_name        = "${local.cluster_identifiers.primary}-global-replication-lag"
  alarm_description = "${local.cluster_identifiers.primary} is more than ${var.replication_lag_alarm_seconds}s behind the writer region. A regional failover now would lose that much data."

  namespace   = "AWS/RDS"
  metric_name = "AuroraGlobalDBReplicationLag" # milliseconds
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_seconds * 1000
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_topic_arns.primary
  ok_actions    = var.alarm_topic_arns.primary
}

resource "aws_cloudwatch_metric_alarm" "replication_lag_secondary" {
  provider = aws.secondary

  alarm_name        = "${local.cluster_identifiers.secondary}-global-replication-lag"
  alarm_description = "${local.cluster_identifiers.secondary} is more than ${var.replication_lag_alarm_seconds}s behind the writer region. A regional failover now would lose that much data."

  namespace   = "AWS/RDS"
  metric_name = "AuroraGlobalDBReplicationLag" # milliseconds
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_seconds * 1000
  treat_missing_data  = "notBreaching"

  alarm_actions = var.alarm_topic_arns.secondary
  ok_actions    = var.alarm_topic_arns.secondary
}
