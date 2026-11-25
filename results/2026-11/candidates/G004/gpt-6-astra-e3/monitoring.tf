resource "aws_sns_topic" "primary" { name = "${var.name}-database-alerts" }
resource "aws_sns_topic" "secondary" {
  provider = aws.secondary
  name     = "${var.name}-database-alerts"
}
resource "aws_sns_topic_subscription" "primary" {
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
resource "aws_sns_topic_subscription" "secondary" {
  provider  = aws.secondary
  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
resource "aws_db_event_subscription" "primary" {
  name             = "${var.name}-primary-events"
  sns_topic        = aws_sns_topic.primary.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
}
resource "aws_db_event_subscription" "secondary" {
  provider         = aws.secondary
  name             = "${var.name}-secondary-events"
  sns_topic        = aws_sns_topic.secondary.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
}
locals {
  # Both sides are monitored for lag so the controls still exist after switchover.
  cluster_alarms = {
    replication_lag = { metric = "AuroraGlobalDBReplicationLag", threshold = 2000, comparison = "GreaterThanThreshold", missing = "notBreaching", description = "Cross-region replication above two seconds; investigate immediately. Milliseconds; only emitted on secondary members." }
    rpo_lag         = { metric = "AuroraGlobalDBRPOLag", threshold = 2000, comparison = "GreaterThanThreshold", missing = "notBreaching", description = "User-transaction RPO lag above two seconds. Milliseconds; only emitted on secondary members." }
  }
  instance_alarms = merge([for index in range(2) : {
    "${index}-cpu"     = { index = index, metric = "CPUUtilization", threshold = 80, comparison = "GreaterThanThreshold" }
    "${index}-memory"  = { index = index, metric = "FreeableMemory", threshold = 1073741824, comparison = "LessThanThreshold" }
    "${index}-storage" = { index = index, metric = "FreeLocalStorage", threshold = 5368709120, comparison = "LessThanThreshold" }
  }]...)
}
resource "aws_cloudwatch_metric_alarm" "primary_lag" {
  for_each            = local.cluster_alarms
  alarm_name          = "${var.name}-primary-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.primary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}
resource "aws_cloudwatch_metric_alarm" "secondary_lag" {
  provider            = aws.secondary
  for_each            = local.cluster_alarms
  alarm_name          = "${var.name}-secondary-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
resource "aws_cloudwatch_metric_alarm" "primary_instance" {
  for_each            = local.instance_alarms
  alarm_name          = "${var.name}-primary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[each.value.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}
resource "aws_cloudwatch_metric_alarm" "secondary_instance" {
  provider            = aws.secondary
  for_each            = local.instance_alarms
  alarm_name          = "${var.name}-secondary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[each.value.index].id }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
