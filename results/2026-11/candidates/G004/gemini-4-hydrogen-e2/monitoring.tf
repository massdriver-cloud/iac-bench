resource "aws_sns_topic" "alarms_primary" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.name_prefix}-aurora-alarms"
  kms_master_key_id = aws_kms_key.primary.id

  tags = {
    Name = "${local.name_prefix}-aurora-alarms-primary"
  }
}

data "aws_iam_policy_document" "sns_alarms_primary" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid    = "AllowCloudWatchAndRDSPublish"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms_primary[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms_primary" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  arn    = aws_sns_topic.alarms_primary[0].arn
  policy = data.aws_iam_policy_document.sns_alarms_primary[0].json
}

resource "aws_sns_topic" "alarms_secondary" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.name_prefix}-aurora-alarms"
  kms_master_key_id = aws_kms_key.secondary.id

  tags = {
    Name = "${local.name_prefix}-aurora-alarms-secondary"
  }
}

data "aws_iam_policy_document" "sns_alarms_secondary" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid    = "AllowCloudWatchAndRDSPublish"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.alarms_secondary[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "alarms_secondary" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  arn    = aws_sns_topic.alarms_secondary[0].arn
  policy = data.aws_iam_policy_document.sns_alarms_secondary[0].json
}

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag exceeds ${var.replication_lag_alarm_threshold_ms}ms RPO threshold"
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_alarm_topic_arn]
  ok_actions    = [local.secondary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  alarm_name          = "${local.name_prefix}-primary-cpu-high"
  alarm_description   = "Primary Aurora PostgreSQL cluster CPU utilization exceeded ${var.cpu_alarm_threshold_percent}%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_alarm_topic_arn]
  ok_actions    = [local.primary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-secondary-cpu-high"
  alarm_description   = "Secondary Aurora PostgreSQL cluster CPU utilization exceeded ${var.cpu_alarm_threshold_percent}%"
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_alarm_topic_arn]
  ok_actions    = [local.secondary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  alarm_name          = "${local.name_prefix}-primary-freeable-memory-low"
  alarm_description   = "Primary Aurora PostgreSQL cluster freeable memory below ${var.freeable_memory_alarm_threshold_bytes} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.freeable_memory_alarm_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_alarm_topic_arn]
  ok_actions    = [local.primary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory_low" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-secondary-freeable-memory-low"
  alarm_description   = "Secondary Aurora PostgreSQL cluster freeable memory below ${var.freeable_memory_alarm_threshold_bytes} bytes"
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.freeable_memory_alarm_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_alarm_topic_arn]
  ok_actions    = [local.secondary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_connections_high" {
  alarm_name          = "${local.name_prefix}-primary-connections-high"
  alarm_description   = "Primary Aurora PostgreSQL connections exceeded ${var.database_connections_alarm_threshold}"
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = var.database_connections_alarm_threshold
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_alarm_topic_arn]
  ok_actions    = [local.primary_alarm_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_deadlocks" {
  alarm_name          = "${local.name_prefix}-primary-deadlocks"
  alarm_description   = "Database deadlocks detected on primary Aurora PostgreSQL cluster"
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 5
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_alarm_topic_arn]
}

resource "aws_db_event_subscription" "primary_cluster" {
  name             = "${local.name_prefix}-primary-cluster-events"
  sns_topic        = local.primary_alarm_topic_arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.cluster_identifier]
  event_categories = ["failover", "failure", "configuration change", "maintenance", "notification"]

  depends_on = [aws_sns_topic_policy.alarms_primary]
}

resource "aws_db_event_subscription" "secondary_cluster" {
  provider = aws.secondary

  name             = "${local.name_prefix}-secondary-cluster-events"
  sns_topic        = local.secondary_alarm_topic_arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.cluster_identifier]
  event_categories = ["failover", "failure", "configuration change", "maintenance", "notification"]

  depends_on = [aws_sns_topic_policy.alarms_secondary]
}
