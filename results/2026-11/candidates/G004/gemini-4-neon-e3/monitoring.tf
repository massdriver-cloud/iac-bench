# ------------------------------------------------------------------------------
# Primary Region Logs, Alerts, RDS Events & DBA CloudWatch Alarms
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_id}-postgresql-logs"
  }
}

resource "aws_sns_topic" "primary_alerts" {
  name              = "${local.primary_cluster_id}-alerts"
  kms_master_key_id = aws_kms_key.primary.id

  tags = {
    Name = "${local.primary_cluster_id}-alerts"
  }
}

data "aws_iam_policy_document" "primary_sns_alerts" {
  statement {
    sid    = "AllowAccountManagement"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["sns:*"]
    resources = [aws_sns_topic.primary_alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAndRDSPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.primary_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.primary_alerts.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "primary_alerts" {
  arn    = aws_sns_topic.primary_alerts.arn
  policy = data.aws_iam_policy_document.primary_sns_alerts.json
}

resource "aws_sns_topic_subscription" "primary_email" {
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.primary_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_db_event_subscription" "primary_cluster" {
  name        = "${local.primary_cluster_id}-cluster-events"
  sns_topic   = aws_sns_topic.primary_alerts.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.primary.id]

  event_categories = [
    "failover",
    "failure",
    "maintenance",
    "notification",
  ]

  tags = {
    Name = "${local.primary_cluster_id}-cluster-events"
  }
}

resource "aws_db_event_subscription" "primary_instances" {
  name        = "${local.primary_cluster_id}-instance-events"
  sns_topic   = aws_sns_topic.primary_alerts.arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.primary[*].id

  event_categories = [
    "availability",
    "deletion",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "recovery",
  ]

  tags = {
    Name = "${local.primary_cluster_id}-instance-events"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  alarm_name          = "${local.primary_cluster_id}-high-cpu"
  alarm_description   = "Average cluster CPU utilization exceeded ${var.alarm_cpu_threshold}% for ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  alarm_name          = "${local.primary_cluster_id}-low-freeable-memory"
  alarm_description   = "Minimum freeable memory dropped below ${var.alarm_freeable_memory_bytes} bytes for ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_freeable_memory_bytes
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_free_local_storage" {
  alarm_name          = "${local.primary_cluster_id}-low-free-local-storage"
  alarm_description   = "Free local storage (temp files/sort spills) dropped below ${var.alarm_free_local_storage_bytes} bytes for ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeLocalStorage"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_free_local_storage_bytes
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_connections" {
  alarm_name          = "${local.primary_cluster_id}-high-connections"
  alarm_description   = "Database connection count exceeded ${var.alarm_connections_threshold} for ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_connections_threshold
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

# PostgreSQL transaction ID (XID) wraparound early warning (1B out of ~2.1B limit)
resource "aws_cloudwatch_metric_alarm" "primary_txid_wraparound" {
  alarm_name          = "${local.primary_cluster_id}-txid-wraparound-risk"
  alarm_description   = "MaximumUsedTransactionIDs exceeded 1,000,000,000 on ${local.primary_cluster_id}; investigate autovacuum urgently to prevent PostgreSQL XID wraparound."
  namespace           = "AWS/RDS"
  metric_name         = "MaximumUsedTransactionIDs"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1000000000
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_replica_lag" {
  count = var.primary_instance_count > 1 ? 1 : 0

  alarm_name          = "${local.primary_cluster_id}-high-replica-lag"
  alarm_description   = "Intra-region Aurora reader replica lag exceeded ${var.alarm_replica_lag_ms} ms for ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_replica_lag_ms
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_deadlocks" {
  alarm_name          = "${local.primary_cluster_id}-deadlocks"
  alarm_description   = "Elevated PostgreSQL deadlock rate detected on ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.primary_alerts.arn]
  ok_actions    = [aws_sns_topic.primary_alerts.arn]
}

# ------------------------------------------------------------------------------
# Secondary Region Logs, Alerts, RDS Events & DBA + Global RPO Alarms
# ------------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.secondary_cluster_id}-postgresql-logs"
  }
}

resource "aws_sns_topic" "secondary_alerts" {
  provider = aws.secondary

  name              = "${local.secondary_cluster_id}-alerts"
  kms_master_key_id = aws_kms_key.secondary.id

  tags = {
    Name = "${local.secondary_cluster_id}-alerts"
  }
}

data "aws_iam_policy_document" "secondary_sns_alerts" {
  provider = aws.secondary

  statement {
    sid    = "AllowAccountManagement"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["sns:*"]
    resources = [aws_sns_topic.secondary_alerts.arn]
  }

  statement {
    sid    = "AllowCloudWatchAndRDSPublish"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.secondary_alerts.arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.secondary_alerts.arn]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_sns_topic_policy" "secondary_alerts" {
  provider = aws.secondary

  arn    = aws_sns_topic.secondary_alerts.arn
  policy = data.aws_iam_policy_document.secondary_sns_alerts.json
}

resource "aws_sns_topic_subscription" "secondary_email" {
  provider = aws.secondary
  for_each = toset(var.alert_email_addresses)

  topic_arn = aws_sns_topic.secondary_alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_db_event_subscription" "secondary_cluster" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-cluster-events"
  sns_topic   = aws_sns_topic.secondary_alerts.arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.secondary.id]

  event_categories = [
    "failover",
    "failure",
    "maintenance",
    "notification",
  ]

  tags = {
    Name = "${local.secondary_cluster_id}-cluster-events"
  }
}

resource "aws_db_event_subscription" "secondary_instances" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-instance-events"
  sns_topic   = aws_sns_topic.secondary_alerts.arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.secondary[*].id

  event_categories = [
    "availability",
    "deletion",
    "failover",
    "failure",
    "low storage",
    "maintenance",
    "recovery",
  ]

  tags = {
    Name = "${local.secondary_cluster_id}-instance-events"
  }
}

# Critical RPO guardrail: alerts if cross-region replication lag exceeds a few
# seconds (default 5000 ms) or stops emitting telemetry.
resource "aws_cloudwatch_metric_alarm" "secondary_global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag"
  alarm_description   = "Aurora Global Database cross-region replication lag exceeded ${var.alarm_global_replication_lag_ms} ms (RPO at risk) for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_global_replication_lag_ms
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-high-cpu"
  alarm_description   = "Average cluster CPU utilization exceeded ${var.alarm_cpu_threshold}% for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_cpu_threshold
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-low-freeable-memory"
  alarm_description   = "Minimum freeable memory dropped below ${var.alarm_freeable_memory_bytes} bytes for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_freeable_memory_bytes
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_free_local_storage" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-low-free-local-storage"
  alarm_description   = "Free local storage (temp files/sort spills) dropped below ${var.alarm_free_local_storage_bytes} bytes for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeLocalStorage"
  statistic           = "Minimum"
  comparison_operator = "LessThanThreshold"
  threshold           = var.alarm_free_local_storage_bytes
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_connections" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-high-connections"
  alarm_description   = "Database connection count exceeded ${var.alarm_connections_threshold} for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "DatabaseConnections"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_connections_threshold
  period              = 300
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_txid_wraparound" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-txid-wraparound-risk"
  alarm_description   = "MaximumUsedTransactionIDs exceeded 1,000,000,000 on ${local.secondary_cluster_id}; investigate autovacuum urgently to prevent PostgreSQL XID wraparound."
  namespace           = "AWS/RDS"
  metric_name         = "MaximumUsedTransactionIDs"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 1000000000
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_replica_lag" {
  provider = aws.secondary
  count    = var.secondary_instance_count > 1 ? 1 : 0

  alarm_name          = "${local.secondary_cluster_id}-high-replica-lag"
  alarm_description   = "Intra-region Aurora reader replica lag exceeded ${var.alarm_replica_lag_ms} ms for ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  statistic           = "Maximum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.alarm_replica_lag_ms
  period              = 60
  evaluation_periods  = 3
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_deadlocks" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-deadlocks"
  alarm_description   = "Elevated PostgreSQL deadlock rate detected on ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  comparison_operator = "GreaterThanThreshold"
  threshold           = 5
  period              = 300
  evaluation_periods  = 2
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.secondary_alerts.arn]
  ok_actions    = [aws_sns_topic.secondary_alerts.arn]
}
