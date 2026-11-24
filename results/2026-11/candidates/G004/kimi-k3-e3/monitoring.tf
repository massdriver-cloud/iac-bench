# =============================================================================
# Alerting
#
# One SNS topic per region (CloudWatch alarm actions must target a topic in
# the alarm's own region). Subscribe the on-call destination(s) to these
# topics - the module deliberately does not decide who gets paged.
#
# The replication-lag alarm is the RPO guardrail: the business allows only a
# few seconds of data loss, so sustained cross-region lag must page someone.
# =============================================================================

resource "aws_sns_topic" "alerts_primary" {
  name = "${local.name_prefix}-db-alerts-${var.primary_region}"

  tags = { Name = "${local.name_prefix}-db-alerts-${var.primary_region}" }
}

resource "aws_sns_topic" "alerts_secondary" {
  provider = aws.secondary

  name = "${local.name_prefix}-db-alerts-${var.secondary_region}"

  tags = { Name = "${local.name_prefix}-db-alerts-${var.secondary_region}" }
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  count = var.primary_instance_count

  alarm_name          = "${local.name_prefix}-primary-${count.index + 1}-cpu-high"
  alarm_description   = "Aurora instance ${local.name_prefix}-primary-${count.index + 1} CPU above ${var.cpu_alarm_threshold_percent}% for 5 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[count.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts_primary.arn]
  ok_actions          = [aws_sns_topic.alerts_primary.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary

  count = var.secondary_instance_count

  alarm_name          = "${local.name_prefix}-secondary-${count.index + 1}-cpu-high"
  alarm_description   = "Aurora instance ${local.name_prefix}-secondary-${count.index + 1} CPU above ${var.cpu_alarm_threshold_percent}% for 5 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[count.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts_secondary.arn]
  ok_actions          = [aws_sns_topic.alerts_secondary.arn]
}

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-global-replication-lag-high"
  alarm_description   = "Aurora global database ${local.name_prefix}: cross-region replication lag above ${var.replication_lag_alarm_threshold_ms} ms. This is the RPO guardrail - investigate before any planned switchover."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  alarm_actions       = [aws_sns_topic.alerts_secondary.arn]
  ok_actions          = [aws_sns_topic.alerts_secondary.arn]
}
