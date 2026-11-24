resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  provider = aws.primary
  for_each = { for instance in aws_rds_cluster_instance.primary : instance.identifier => instance }

  alarm_name          = "${each.key}-cpu-high"
  alarm_description   = "Aurora instance ${each.key} has sustained high CPU. Check queries and capacity; sustained pressure can affect availability and replication."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]

  depends_on = [aws_sns_topic_policy.primary_alerts]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary
  for_each = { for instance in aws_rds_cluster_instance.secondary : instance.identifier => instance }

  alarm_name          = "${each.key}-cpu-high"
  alarm_description   = "Aurora recovery instance ${each.key} has sustained high CPU. Capacity must remain sufficient to take over writes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]

  depends_on = [aws_sns_topic_policy.secondary_alerts]
}

resource "aws_cloudwatch_metric_alarm" "primary_memory" {
  provider = aws.primary
  for_each = { for instance in aws_rds_cluster_instance.primary : instance.identifier => instance }

  alarm_name          = "${each.key}-memory-low"
  alarm_description   = "Aurora instance ${each.key} has less than 256 MiB freeable memory for three minutes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]

  depends_on = [aws_sns_topic_policy.primary_alerts]
}

resource "aws_cloudwatch_metric_alarm" "secondary_memory" {
  provider = aws.secondary
  for_each = { for instance in aws_rds_cluster_instance.secondary : instance.identifier => instance }

  alarm_name          = "${each.key}-memory-low"
  alarm_description   = "Aurora recovery instance ${each.key} has less than 256 MiB freeable memory for three minutes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]

  depends_on = [aws_sns_topic_policy.secondary_alerts]
}

resource "aws_cloudwatch_metric_alarm" "global_rpo" {
  provider = aws.secondary

  alarm_name          = "${var.name}-aurora-global-rpo-high"
  alarm_description   = "The recovery cluster RPO exceeds ${var.rpo_alarm_threshold_seconds} seconds. Do not fail over until the recovery objective and application impact are understood."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rpo_alarm_threshold_seconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }
  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]

  depends_on = [aws_sns_topic_policy.secondary_alerts]
}
