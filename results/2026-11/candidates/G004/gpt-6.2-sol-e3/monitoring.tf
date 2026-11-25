resource "aws_sns_topic" "alarms" {
  for_each = local.key_regions
  region   = each.value
  name     = "${local.name}-aurora-alarms"
}

data "aws_iam_policy_document" "alarms" {
  for_each = local.key_regions
  statement {
    sid       = "EnableAccountIAM"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.alarms[each.key].arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
  statement {
    sid       = "AllowThisDatabasesAlarms"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms[each.key].arn]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:cloudwatch:${each.value}:${local.account_id}:alarm:${local.name}-aurora-*"]
    }
  }
}

resource "aws_sns_topic_policy" "alarms" {
  for_each = local.key_regions
  region   = each.value
  arn      = aws_sns_topic.alarms[each.key].arn
  policy   = data.aws_iam_policy_document.alarms[each.key].json
}

resource "aws_sns_topic_subscription" "on_call" {
  for_each   = local.key_regions
  region     = each.value
  topic_arn  = aws_sns_topic.alarms[each.key].arn
  protocol   = "email"
  endpoint   = var.alarm_email
  depends_on = [aws_sns_topic_policy.alarms]
}

# This metric is emitted by the secondary cluster and includes lag relevant
# to losing committed writes. Missing telemetry is also a loss of DR visibility.
resource "aws_cloudwatch_metric_alarm" "rpo" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-aurora-global-rpo-lag"
  alarm_description   = "Recovery replication lag crossed 3 seconds or is unknown. Check global topology and recovery readiness."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  unit                = "Milliseconds"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 1
  threshold           = 3000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }
  alarm_actions = [aws_sns_topic.alarms["secondary"].arn]
  ok_actions    = [aws_sns_topic.alarms["secondary"].arn]
  depends_on    = [aws_sns_topic_policy.alarms, aws_rds_cluster_instance.secondary]
}

locals {
  instance_alarms = {
    for key in setproduct(["primary", "secondary"], [0, 1]) : "${key[0]}-${key[1] + 1}" => {
      region_key = key[0]
      instance   = key[0] == "primary" ? aws_rds_cluster_instance.primary[key[1]].identifier : aws_rds_cluster_instance.secondary[key[1]].identifier
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "cpu" {
  for_each            = local.instance_alarms
  region              = local.key_regions[each.value.region_key]
  alarm_name          = "${local.name}-aurora-${each.key}-cpu"
  alarm_description   = "Sustained database CPU saturation. Check workload and failover capacity."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  threshold           = 85
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "missing"
  dimensions = {
    DBInstanceIdentifier = each.value.instance
  }
  alarm_actions = [aws_sns_topic.alarms[each.value.region_key].arn]
  depends_on    = [aws_sns_topic_policy.alarms]
}
