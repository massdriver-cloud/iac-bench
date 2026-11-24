################################################################################
# Regional KMS-Encrypted SNS Alert Topics (Created Unless Existing ARN Passed)
################################################################################

resource "aws_sns_topic" "primary_alerts" {
  provider = aws.primary
  count    = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.primary_cluster_id}-alerts"
  kms_master_key_id = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_id}-alerts"
  }
}

data "aws_iam_policy_document" "primary_sns_policy" {
  provider = aws.primary
  count    = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.primary_alerts[0].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAndRDSEventsPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.primary_alerts[0].arn]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.rds.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "primary_alerts" {
  provider = aws.primary
  count    = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  arn    = aws_sns_topic.primary_alerts[0].arn
  policy = data.aws_iam_policy_document.primary_sns_policy[0].json
}

resource "aws_sns_topic" "secondary_alerts" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.secondary_cluster_id}-alerts"
  kms_master_key_id = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.secondary_cluster_id}-alerts"
  }
}

data "aws_iam_policy_document" "secondary_sns_policy" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["sns:*"]
    resources = [aws_sns_topic.secondary_alerts[0].arn]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid       = "AllowCloudWatchAndRDSEventsPublish"
    effect    = "Allow"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.secondary_alerts[0].arn]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.rds.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "secondary_alerts" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  arn    = aws_sns_topic.secondary_alerts[0].arn
  policy = data.aws_iam_policy_document.secondary_sns_policy[0].json
}

################################################################################
# Primary Region CloudWatch Alarms
################################################################################

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Aurora PostgreSQL primary cluster CPUUtilization exceeded ${var.cpu_alarm_threshold_percent}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-freeable-memory-low"
  alarm_description   = "Aurora PostgreSQL primary cluster FreeableMemory dropped below ${var.freeable_memory_alarm_threshold_bytes} bytes."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.freeable_memory_alarm_threshold_bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_connections_high" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-connections-high"
  alarm_description   = "Aurora PostgreSQL primary cluster DatabaseConnections exceeded ${var.connections_alarm_threshold}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.connections_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_xid_wraparound" {
  provider = aws.primary

  alarm_name          = "${local.primary_cluster_id}-xid-wraparound-risk"
  alarm_description   = "PostgreSQL MaximumUsedTransactionIDs exceeded 1B (early warning for transaction ID wraparound)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MaximumUsedTransactionIDs"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1000000000
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_replica_lag" {
  provider = aws.primary
  count    = var.primary_instance_count > 1 ? 1 : 0

  alarm_name          = "${local.primary_cluster_id}-reader-replica-lag"
  alarm_description   = "Intra-region Aurora reader replica lag exceeded 1000 ms."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1000
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    Role                = "READER"
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

################################################################################
# Secondary Region CloudWatch Alarms (Includes Cross-Region RPO Guardrail)
################################################################################

resource "aws_cloudwatch_metric_alarm" "secondary_global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-rpo-lag-high"
  alarm_description   = "CRITICAL RPO ALERT: AuroraGlobalDBReplicationLag from ${var.primary_region} to ${var.secondary_region} exceeded ${var.global_replication_lag_alarm_ms} ms."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.global_replication_lag_alarm_ms
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-cpu-high"
  alarm_description   = "Aurora PostgreSQL secondary cluster CPUUtilization exceeded ${var.cpu_alarm_threshold_percent}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.cpu_alarm_threshold_percent
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory_low" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-freeable-memory-low"
  alarm_description   = "Aurora PostgreSQL secondary cluster FreeableMemory dropped below ${var.freeable_memory_alarm_threshold_bytes} bytes."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 5
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.freeable_memory_alarm_threshold_bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_connections_high" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-connections-high"
  alarm_description   = "Aurora PostgreSQL secondary cluster DatabaseConnections exceeded ${var.connections_alarm_threshold}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.connections_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_xid_wraparound" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-xid-wraparound-risk"
  alarm_description   = "PostgreSQL MaximumUsedTransactionIDs exceeded 1B in secondary cluster."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "MaximumUsedTransactionIDs"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Maximum"
  threshold           = 1000000000
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

################################################################################
# Regional RDS Event Subscriptions (Failover, Failure, Maintenance, Availability)
################################################################################

resource "aws_db_event_subscription" "primary_cluster" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-cluster-events"
  sns_topic   = local.primary_sns_topic_arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.primary.cluster_identifier]

  event_categories = [
    "failover",
    "failure",
    "global-failover",
    "maintenance",
    "notification"
  ]
}

resource "aws_db_event_subscription" "primary_instances" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-instance-events"
  sns_topic   = local.primary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.primary[*].identifier

  event_categories = [
    "availability",
    "configuration change",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "recovery"
  ]
}

resource "aws_db_event_subscription" "secondary_cluster" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-cluster-events"
  sns_topic   = local.secondary_sns_topic_arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.secondary.cluster_identifier]

  event_categories = [
    "failover",
    "failure",
    "global-failover",
    "maintenance",
    "notification"
  ]
}

resource "aws_db_event_subscription" "secondary_instances" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-instance-events"
  sns_topic   = local.secondary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.secondary[*].identifier

  event_categories = [
    "availability",
    "configuration change",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "recovery"
  ]
}
