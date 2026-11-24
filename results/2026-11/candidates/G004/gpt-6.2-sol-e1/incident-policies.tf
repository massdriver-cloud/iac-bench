locals {
  alarm_topics = {
    for region, topic in {
      (var.regions.primary)   = var.incident_topic_arns.primary == null ? local.primary_topic : null
      (var.regions.secondary) = var.incident_topic_arns.secondary == null ? local.secondary_topic : null
    } : region => topic if(region == var.regions.primary ? var.incident_topic_arns.primary == null : var.incident_topic_arns.secondary == null)
  }
}

data "aws_iam_policy_document" "incident" {
  for_each = local.alarm_topics

  statement {
    sid       = "AccountAdministration"
    actions   = ["sns:*"]
    resources = [each.value]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid       = "RDSNotifications"
    actions   = ["sns:Publish"]
    resources = [each.value]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid       = "LagAlarmNotifications"
    actions   = ["sns:Publish"]
    resources = [each.value]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = ["arn:${data.aws_partition.current.partition}:cloudwatch:${each.key}:${local.account_id}:alarm:${local.name}-aurora-rpo-lag"]
    }
  }
}

resource "aws_sns_topic_policy" "primary" {
  count  = var.incident_topic_arns.primary == null ? 1 : 0
  arn    = local.primary_topic
  policy = data.aws_iam_policy_document.incident[var.regions.primary].json
}

resource "aws_sns_topic_policy" "secondary" {
  provider = aws.secondary
  count    = var.incident_topic_arns.secondary == null ? 1 : 0
  arn      = local.secondary_topic
  policy   = data.aws_iam_policy_document.incident[var.regions.secondary].json
}
