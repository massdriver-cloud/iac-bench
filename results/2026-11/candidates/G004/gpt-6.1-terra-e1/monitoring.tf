resource "aws_cloudwatch_metric_alarm" "global_lag" {
  provider            = aws.secondary
  count               = 2
  alarm_name          = "${local.name}-secondary-${count.index + 1}-global-replication-lag"
  alarm_description   = "Secondary global replication lag is over 5 seconds; RPO is at risk."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[count.index].identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 5000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.secondary_alarm_topic_arn]
  ok_actions          = [var.secondary_alarm_topic_arn]
}
resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  count               = 2
  alarm_name          = "${local.name}-primary-${count.index + 1}-cpu"
  alarm_description   = "High database instance CPU"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[count.index].identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [var.primary_alarm_topic_arn]
}
