locals {
  alarm_thresholds = {
    cpu    = { metric = "CPUUtilization", threshold = 80, comparison = "GreaterThanThreshold", statistic = "Average" }
    memory = { metric = "FreeableMemory", threshold = 1073741824, comparison = "LessThanThreshold", statistic = "Minimum" }
  }
  instance_alarms = { for item in setproduct([0, 1], keys(local.alarm_thresholds)) : "${item[0]}-${item[1]}" => {
    index = item[0], config = local.alarm_thresholds[item[1]]
  } }
}

resource "aws_sns_topic" "primary" { name = "${local.name}-database-alerts" }
resource "aws_sns_topic" "secondary" {
  provider = aws.secondary
  name     = "${local.name}-database-alerts"
}

# SNS messages contain operational metadata, not database contents or credentials.
# Restrict publisher access to this account and the monitoring services.
data "aws_iam_policy_document" "alerts_primary" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.primary.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    actions   = ["sns:*"]
    resources = [aws_sns_topic.primary.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

data "aws_iam_policy_document" "alerts_secondary" {
  statement {
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.secondary.arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "events.rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
  statement {
    actions   = ["sns:*"]
    resources = [aws_sns_topic.secondary.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
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

resource "aws_sns_topic_subscription" "primary" {
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
resource "aws_sns_topic_subscription" "secondary" {
  provider  = aws.secondary
  count     = var.alarm_email == null ? 0 : 1
  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}

resource "aws_cloudwatch_metric_alarm" "primary" {
  for_each            = local.instance_alarms
  alarm_name          = "${local.name}-primary-${each.key}"
  alarm_description   = "Aurora instance capacity pressure; investigate before saturation."
  namespace           = "AWS/RDS"
  metric_name         = each.value.config.metric
  statistic           = each.value.config.statistic
  comparison_operator = each.value.config.comparison
  threshold           = each.value.config.threshold
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[each.value.index].identifier }
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary" {
  provider            = aws.secondary
  for_each            = local.instance_alarms
  alarm_name          = "${local.name}-secondary-${each.key}"
  alarm_description   = "Aurora DR capacity pressure; warm standby must handle full production load."
  namespace           = "AWS/RDS"
  metric_name         = each.value.config.metric
  statistic           = each.value.config.statistic
  comparison_operator = each.value.config.comparison
  threshold           = each.value.config.threshold
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "breaching"
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[each.value.index].identifier }
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}

resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-global-replication-lag"
  alarm_description   = "Cross-region replication exceeds 1 second (metric is milliseconds). Page on-call; this is not an automatic failover trigger or an RPO guarantee."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1000
  period              = 60
  evaluation_periods  = 1
  treat_missing_data  = "breaching"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}

resource "aws_db_event_subscription" "primary" {
  name        = "${local.name}-primary-events"
  sns_topic   = aws_sns_topic.primary.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.primary.id]
  enabled     = true
  depends_on  = [aws_sns_topic_policy.primary]
}
resource "aws_db_event_subscription" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-secondary-events"
  sns_topic   = aws_sns_topic.secondary.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.secondary.id]
  enabled     = true
  depends_on  = [aws_sns_topic_policy.secondary]
}
