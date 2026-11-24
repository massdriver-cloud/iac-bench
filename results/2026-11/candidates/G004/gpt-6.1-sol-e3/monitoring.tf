resource "aws_sns_topic" "primary" {
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.notifications_primary.arn
}
resource "aws_sns_topic" "secondary" {
  provider          = aws.secondary
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.notifications_secondary.arn
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
data "aws_iam_policy_document" "alerts_primary" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.primary.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
data "aws_iam_policy_document" "alerts_secondary" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.secondary.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}
resource "aws_sns_topic_policy" "primary" {
  arn    = aws_sns_topic.primary.arn
  policy = data.aws_iam_policy_document.alerts_primary.json
}
resource "aws_sns_topic_policy" "secondary" {
  provider = aws.secondary
  arn      = aws_sns_topic.secondary.arn
  policy   = data.aws_iam_policy_document.alerts_secondary.json
}

# PostgreSQL RPO lag is measured in milliseconds. Detect missing telemetry in the DR region.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.prefix}-global-rpo-at-risk"
  alarm_description   = "Global RPO lag exceeds 1s. Target RPO <=5s; page immediately, inspect secondary lag and write availability. See RUNBOOK.md."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1000
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
locals {
  instance_alarm_specs = merge([
    for i in range(var.instances_per_region) : {
      "${i}-cpu" = {
        index = i, metric = "CPUUtilization", statistic = "Average", threshold = 80, comparison = "GreaterThanThreshold"
      }
      "${i}-memory" = {
        index = i, metric = "FreeableMemory", statistic = "Minimum", threshold = 1073741824, comparison = "LessThanThreshold"
      }
      "${i}-storage" = {
        index = i, metric = "FreeLocalStorage", statistic = "Minimum", threshold = 5368709120, comparison = "LessThanThreshold"
      }
    }
  ]...)
}
resource "aws_cloudwatch_metric_alarm" "primary" {
  for_each            = local.instance_alarm_specs
  alarm_name          = "${local.prefix}-primary-${each.key}"
  alarm_description   = "Aurora resource pressure. Investigate before failover capacity or availability is affected."
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[each.value.index].id }
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}
resource "aws_cloudwatch_metric_alarm" "secondary" {
  provider            = aws.secondary
  for_each            = local.instance_alarm_specs
  alarm_name          = "${local.prefix}-secondary-${each.key}"
  alarm_description   = "Aurora DR resource pressure. Recovery capacity must remain healthy."
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[each.value.index].id }
  statistic           = each.value.statistic
  comparison_operator = each.value.comparison
  threshold           = each.value.threshold
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
# All cluster events, including newly introduced recovery event categories.
resource "aws_db_event_subscription" "primary" {
  name        = "${local.prefix}-primary-events"
  sns_topic   = aws_sns_topic.primary.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.primary.id]
  depends_on  = [aws_sns_topic_policy.primary]
}
resource "aws_db_event_subscription" "secondary" {
  provider    = aws.secondary
  name        = "${local.prefix}-secondary-events"
  sns_topic   = aws_sns_topic.secondary.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.secondary.id]
  depends_on  = [aws_sns_topic_policy.secondary]
}
