resource "aws_sns_topic" "primary" {
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.primary.arn
}
resource "aws_sns_topic" "secondary" {
  provider          = aws.secondary
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.secondary.arn
}

data "aws_iam_policy_document" "notifications" {
  for_each = { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn }
  statement {
    sid       = "Owner"
    actions   = ["SNS:*"]
    resources = [each.value]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "CloudWatchPublish"
    actions   = ["sns:Publish"]
    resources = [each.value]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
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
  policy = data.aws_iam_policy_document.notifications["primary"].json
}
resource "aws_sns_topic_policy" "secondary" {
  provider = aws.secondary
  arn      = aws_sns_topic.secondary.arn
  policy   = data.aws_iam_policy_document.notifications["secondary"].json
}
resource "aws_sns_topic_subscription" "primary" {
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
resource "aws_sns_topic_subscription" "secondary" {
  provider  = aws.secondary
  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "rpo" {
  provider            = aws.secondary
  alarm_name          = "${local.prefix}-global-rpo-over-three-seconds"
  alarm_description   = "PAGE: committed-write RPO lag exceeds 3 seconds, or telemetry is absent. Do not assume the write-loss objective can be met. See README failover procedure."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
  depends_on          = [aws_sns_topic_policy.secondary]
}
resource "aws_cloudwatch_metric_alarm" "replication" {
  provider            = aws.secondary
  alarm_name          = "${local.prefix}-global-replication-lag"
  alarm_description   = "PAGE: cross-region storage replication exceeds 3 seconds or metrics are unavailable; investigate regional health and prepare managed failover."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
  depends_on          = [aws_sns_topic_policy.secondary]
}
locals {
  instance_alarms = merge([
    for i in range(var.instances_per_region) : {
      "${i}-cpu"    = { index = i, metric = "CPUUtilization", threshold = 85, comparison = "GreaterThanThreshold", statistic = "Average" }
      "${i}-memory" = { index = i, metric = "FreeableMemory", threshold = 1073741824, comparison = "LessThanThreshold", statistic = "Minimum" }
    }
  ]...)
}
resource "aws_cloudwatch_metric_alarm" "primary_instance" {
  for_each            = local.instance_alarms
  alarm_name          = "${local.prefix}-primary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[each.value.index].id }
  statistic           = each.value.statistic
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
  depends_on          = [aws_sns_topic_policy.primary]
}
resource "aws_cloudwatch_metric_alarm" "secondary_instance" {
  provider            = aws.secondary
  for_each            = local.instance_alarms
  alarm_name          = "${local.prefix}-secondary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[each.value.index].id }
  statistic           = each.value.statistic
  period              = 60
  evaluation_periods  = 3
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
  depends_on          = [aws_sns_topic_policy.secondary]
}

output "alert_topic_arns" {
  description = "Both must feed a 24x7 paging service. Email subscriptions need confirmation."
  value       = { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn }
}
