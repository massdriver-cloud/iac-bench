locals {
  monitoring_regions = { primary = var.primary_region, secondary = var.secondary_region }
  alert_key_policies = {
    for side, region in local.monitoring_regions : side => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        },
        {
          Effect    = "Allow"
          Principal = { Service = "cloudwatch.amazonaws.com" }
          Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
          Resource  = "*"
          Condition = {
            StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
            ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudwatch:${region}:${data.aws_caller_identity.current.account_id}:alarm:${local.prefix}-${side}-*" }
          }
        }
      ]
    })
  }
  alert_topic_policies = {
    for side, region in local.monitoring_regions : side => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Effect    = "Allow"
          Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "SNS:*"
          Resource  = "arn:${data.aws_partition.current.partition}:sns:${region}:${data.aws_caller_identity.current.account_id}:${local.prefix}-${side}-database-alerts"
        },
        {
          Effect    = "Allow"
          Principal = { Service = "cloudwatch.amazonaws.com" }
          Action    = "SNS:Publish"
          Resource  = "arn:${data.aws_partition.current.partition}:sns:${region}:${data.aws_caller_identity.current.account_id}:${local.prefix}-${side}-database-alerts"
          Condition = {
            StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id }
            ArnLike      = { "aws:SourceArn" = "arn:${data.aws_partition.current.partition}:cloudwatch:${region}:${data.aws_caller_identity.current.account_id}:alarm:${local.prefix}-${side}-*" }
          }
        }
      ]
    })
  }
  instance_alarm_definitions = {
    cpu = {
      metric      = "CPUUtilization", statistic = "Average", threshold = 80,
      comparison  = "GreaterThanThreshold", periods = 5, missing = "missing",
      description = "Sustained CPU pressure; investigate capacity and DR readiness."
    }
    memory = {
      metric      = "FreeableMemory", statistic = "Average", threshold = 1073741824,
      comparison  = "LessThanThreshold", periods = 5, missing = "missing",
      description = "Less than 1 GiB free memory; investigate load and capacity."
    }
    availability = {
      metric      = "EngineUptime", statistic = "Minimum", threshold = 1,
      comparison  = "LessThanThreshold", periods = 2, missing = "breaching",
      description = "Engine restarted or telemetry absent. Check application probes and the DR runbook."
    }
  }
  instance_alarms = {
    for side in ["primary", "secondary"] : side => merge([
      for i in range(2) : {
        for key, definition in local.instance_alarm_definitions : "${i}-${key}" => merge(definition, {
          identifier = "${local.prefix}-${side}-${i + 1}", suffix = key
        })
      }
    ]...)
  }
}
resource "aws_kms_key" "primary_alerts" {
  description             = "Encrypt Aurora operational notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.alert_key_policies.primary
}
resource "aws_kms_key" "secondary_alerts" {
  provider                = aws.secondary
  description             = "Encrypt Aurora operational notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.alert_key_policies.secondary
}
resource "aws_sns_topic" "primary" {
  name              = "${local.prefix}-primary-database-alerts"
  kms_master_key_id = aws_kms_key.primary_alerts.arn
}
resource "aws_sns_topic" "secondary" {
  provider          = aws.secondary
  name              = "${local.prefix}-secondary-database-alerts"
  kms_master_key_id = aws_kms_key.secondary_alerts.arn
}
resource "aws_sns_topic_policy" "primary" {
  arn    = aws_sns_topic.primary.arn
  policy = local.alert_topic_policies.primary
}
resource "aws_sns_topic_policy" "secondary" {
  provider = aws.secondary
  arn      = aws_sns_topic.secondary.arn
  policy   = local.alert_topic_policies.secondary
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
resource "aws_cloudwatch_metric_alarm" "primary" {
  for_each            = local.instance_alarms.primary
  alarm_name          = "${local.prefix}-primary-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = each.value.statistic
  period              = 60
  evaluation_periods  = each.value.periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}
resource "aws_cloudwatch_metric_alarm" "secondary" {
  provider            = aws.secondary
  for_each            = local.instance_alarms.secondary
  alarm_name          = "${local.prefix}-secondary-${each.key}"
  alarm_description   = each.value.description
  namespace           = "AWS/RDS"
  metric_name         = each.value.metric
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = each.value.statistic
  period              = 60
  evaluation_periods  = each.value.periods
  threshold           = each.value.threshold
  comparison_operator = each.value.comparison
  treat_missing_data  = each.value.missing
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.prefix}-secondary-global-replication-lag"
  alarm_description   = "Replication exceeds 3s or telemetry missing. Early warning, NOT a guaranteed maximum data loss. See recovery runbook."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
output "alarm_topic_arns" {
  value = { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn }
}
