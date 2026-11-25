locals {
  # The AWS-managed aws/sns key cannot grant CloudWatch/RDS access. Custom
  # regional keys make encrypted alert delivery work for both publishers.
  alert_kms_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "EnableAccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid    = "AllowAlertServices"
        Effect = "Allow"
        Principal = {
          Service = [
            "cloudwatch.${data.aws_partition.primary.dns_suffix}",
            "rds.${data.aws_partition.primary.dns_suffix}",
            "sns.${data.aws_partition.primary.dns_suffix}"
          ]
        }
        Action = [
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:Encrypt",
          "kms:GenerateDataKey*",
          "kms:ReEncrypt*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.primary.account_id }
        }
      }
    ]
  })
}

resource "aws_kms_key" "primary_alerts" {
  provider = aws.primary

  description             = "${var.name} Aurora primary alert topic in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = local.alert_kms_policy
}

resource "aws_kms_alias" "primary_alerts" {
  provider = aws.primary

  name          = "alias/${var.name}-aurora-primary-alerts"
  target_key_id = aws_kms_key.primary_alerts.key_id
}

resource "aws_kms_key" "secondary_alerts" {
  provider = aws.secondary

  description             = "${var.name} Aurora recovery alert topic in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = local.alert_kms_policy
}

resource "aws_kms_alias" "secondary_alerts" {
  provider = aws.secondary

  name          = "alias/${var.name}-aurora-secondary-alerts"
  target_key_id = aws_kms_key.secondary_alerts.key_id
}

resource "aws_sns_topic" "primary_alerts" {
  provider = aws.primary

  name              = "${var.name}-aurora-primary-alerts"
  display_name      = "${var.name} Aurora primary alerts"
  kms_master_key_id = aws_kms_key.primary_alerts.arn
}

resource "aws_sns_topic" "secondary_alerts" {
  provider = aws.secondary

  name              = "${var.name}-aurora-secondary-alerts"
  display_name      = "${var.name} Aurora recovery alerts"
  kms_master_key_id = aws_kms_key.secondary_alerts.arn
}

locals {
  primary_alert_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root" }
        Action    = "SNS:*"
        Resource  = aws_sns_topic.primary_alerts.arn
      },
      {
        Sid       = "CloudWatchAndRDSPublish"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.${data.aws_partition.primary.dns_suffix}", "rds.${data.aws_partition.primary.dns_suffix}"] }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.primary_alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.primary.account_id }
        }
      }
    ]
  })

  secondary_alert_topic_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root" }
        Action    = "SNS:*"
        Resource  = aws_sns_topic.secondary_alerts.arn
      },
      {
        Sid       = "CloudWatchAndRDSPublish"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.${data.aws_partition.primary.dns_suffix}", "rds.${data.aws_partition.primary.dns_suffix}"] }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.secondary_alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.primary.account_id }
        }
      }
    ]
  })
}

resource "aws_sns_topic_policy" "primary_alerts" {
  provider = aws.primary

  arn    = aws_sns_topic.primary_alerts.arn
  policy = local.primary_alert_topic_policy
}

resource "aws_sns_topic_policy" "secondary_alerts" {
  provider = aws.secondary

  arn    = aws_sns_topic.secondary_alerts.arn
  policy = local.secondary_alert_topic_policy
}

resource "aws_sns_topic_subscription" "primary_email" {
  provider = aws.primary
  for_each = toset(var.alarm_email_endpoints)

  topic_arn = aws_sns_topic.primary_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "secondary_email" {
  provider = aws.secondary
  for_each = toset(var.alarm_email_endpoints)

  topic_arn = aws_sns_topic.secondary_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_db_event_subscription" "primary" {
  provider = aws.primary

  name             = "${var.name}-aurora-primary-events"
  sns_topic        = aws_sns_topic.primary_alerts.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
  enabled          = true

  depends_on = [aws_sns_topic_policy.primary_alerts]
}

resource "aws_db_event_subscription" "secondary" {
  provider = aws.secondary

  name             = "${var.name}-aurora-secondary-events"
  sns_topic        = aws_sns_topic.secondary_alerts.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
  enabled          = true

  depends_on = [aws_sns_topic_policy.secondary_alerts]
}
