resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-global-replication-lag"
  alarm_description   = "Aurora global replication lag exceeds 1 second, or replication telemetry is missing. Investigate RPO risk."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = tolist(var.secondary_alarm_topic_arns)
  ok_actions          = tolist(var.secondary_alarm_topic_arns)
  tags                = local.tags
  lifecycle {
    precondition {
      condition     = alltrue([for arn in var.secondary_alarm_topic_arns : split(":", arn)[3] == var.secondary_region])
      error_message = "Alarm topics must be in the secondary region."
    }
  }
}
