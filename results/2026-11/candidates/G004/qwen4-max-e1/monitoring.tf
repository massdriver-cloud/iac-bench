# ---------------------------------------------------------------------------
# Alerting. One SNS topic per region (CloudWatch alarms act on same-region
# topics), with alarms for the failure modes that matter for this SLO:
#   * instance CPU saturation (both regions)
#   * memory pressure on primary instances
#   * global-database RPO lag - pages if replication falls > 10s behind,
#     i.e. before the "few seconds of writes" business bar is at risk
# ---------------------------------------------------------------------------

resource "aws_sns_topic" "primary" {
  name = "${local.name}-db-alerts"
  tags = var.tags
}

resource "aws_sns_topic" "secondary" {
  provider = aws.secondary

  name = "${local.name}-db-alerts"
  tags = var.tags
}

resource "aws_sns_topic_subscription" "primary_email" {
  count = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_sns_topic_subscription" "secondary_email" {
  provider = aws.secondary
  count    = var.alarm_email == null ? 0 : 1

  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  count = var.primary_instance_count

  alarm_name          = "${local.name}-${count.index + 1}-cpu-high"
  alarm_description   = "CPU > 80% for 10 minutes on ${local.name} instance ${count.index + 1}"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[count.index].identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  count = var.primary_instance_count

  alarm_name          = "${local.name}-${count.index + 1}-memory-low"
  alarm_description   = "Freeable memory < 256 MiB for 10 minutes on ${local.name} instance ${count.index + 1}"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[count.index].identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  alarm_name          = "${local.name}-secondary-${count.index + 1}-cpu-high"
  alarm_description   = "CPU > 80% for 10 minutes on ${local.name} DR instance ${count.index + 1}"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[count.index].identifier }
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 2
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
  tags                = var.tags
}

# RPO lag of the global database, published in the secondary region in
# milliseconds. The business tolerates "a few seconds" of lost writes; alert
# at 10 seconds of lag so operators act before the bar is breached.
resource "aws_cloudwatch_metric_alarm" "global_rpo_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name}-global-rpo-lag"
  alarm_description   = "Aurora global database RPO lag > 10s: cross-region failover would lose more than the allowed few seconds of writes"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 10000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
  tags                = var.tags
}
