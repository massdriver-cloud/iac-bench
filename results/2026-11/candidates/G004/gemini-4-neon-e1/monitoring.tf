################################################################################
# Regional KMS-Encrypted SNS Topics for Alarms & RDS Failover Events
################################################################################

resource "aws_sns_topic" "primary_alerts" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.primary_cluster_id}-alerts"
  kms_master_key_id = aws_kms_key.primary.arn

  tags = {
    Name = "${local.primary_cluster_id}-alerts"
    Role = "primary"
  }
}

data "aws_iam_policy_document" "primary_sns_policy" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid     = "AllowCloudWatchAndRdsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    resources = [aws_sns_topic.primary_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_sns_topic_policy" "primary_alerts" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

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
    Role = "secondary"
  }
}

data "aws_iam_policy_document" "secondary_sns_policy" {
  count = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  statement {
    sid     = "AllowCloudWatchAndRdsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    resources = [aws_sns_topic.secondary_alerts[0].arn]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
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
  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Aurora primary cluster ${local.primary_cluster_id} average CPU exceeded ${var.cpu_alarm_threshold_percent}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
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
  alarm_name          = "${local.primary_cluster_id}-freeable-memory-low"
  alarm_description   = "Aurora primary cluster ${local.primary_cluster_id} FreeableMemory dropped below ${local.primary_freeable_memory_threshold_bytes} bytes."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = local.primary_freeable_memory_threshold_bytes
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_connections_high" {
  alarm_name          = "${local.primary_cluster_id}-connections-high"
  alarm_description   = "Aurora primary cluster ${local.primary_cluster_id} DatabaseConnections exceeded ${var.database_connections_alarm_threshold}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.database_connections_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_commit_latency_high" {
  alarm_name          = "${local.primary_cluster_id}-commit-latency-high"
  alarm_description   = "Aurora primary writer ${local.primary_cluster_id} CommitLatency exceeded ${var.commit_latency_alarm_threshold_ms} ms."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CommitLatency"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.commit_latency_alarm_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    Role                = "WRITER"
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_replica_lag_high" {
  alarm_name          = "${local.primary_cluster_id}-replica-lag-high"
  alarm_description   = "Aurora primary cluster ${local.primary_cluster_id} in-region AuroraReplicaLag exceeded ${var.replica_lag_alarm_threshold_ms} ms."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "AuroraReplicaLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replica_lag_alarm_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
    Role                = "READER"
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

################################################################################
# Secondary Region CloudWatch Alarms (Independent DR Region & RPO Guardrail)
################################################################################

resource "aws_cloudwatch_metric_alarm" "secondary_global_replication_lag_high" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-rpo-lag-high"
  alarm_description   = "CRITICAL RPO ALERT: Aurora Global Database cross-region replication lag to ${var.secondary_region} exceeded ${var.global_replication_lag_alarm_threshold_ms} ms."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.global_replication_lag_alarm_threshold_ms
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-cpu-high"
  alarm_description   = "Aurora secondary cluster ${local.secondary_cluster_id} average CPU exceeded ${var.cpu_alarm_threshold_percent}%."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
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
  alarm_description   = "Aurora secondary cluster ${local.secondary_cluster_id} FreeableMemory dropped below ${local.secondary_freeable_memory_threshold_bytes} bytes."
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = local.secondary_freeable_memory_threshold_bytes
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
  alarm_description   = "Aurora secondary cluster ${local.secondary_cluster_id} DatabaseConnections exceeded ${var.database_connections_alarm_threshold}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "DatabaseConnections"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.database_connections_alarm_threshold
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

################################################################################
# RDS Event Subscriptions (Failover, Failure & Availability Notifications)
################################################################################

resource "aws_db_event_subscription" "primary_cluster" {
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

  tags = {
    Name = "${local.primary_cluster_id}-cluster-events"
    Role = "primary"
  }
}

resource "aws_db_event_subscription" "primary_instances" {
  name        = "${local.primary_cluster_id}-instance-events"
  sns_topic   = local.primary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.primary[*].identifier

  event_categories = [
    "availability",
    "failover",
    "failure",
    "low storage",
    "recovery"
  ]

  tags = {
    Name = "${local.primary_cluster_id}-instance-events"
    Role = "primary"
  }
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

  tags = {
    Name = "${local.secondary_cluster_id}-cluster-events"
    Role = "secondary"
  }
}

resource "aws_db_event_subscription" "secondary_instances" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-instance-events"
  sns_topic   = local.secondary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.secondary[*].identifier

  event_categories = [
    "availability",
    "failover",
    "failure",
    "low storage",
    "recovery"
  ]

  tags = {
    Name = "${local.secondary_cluster_id}-instance-events"
    Role = "secondary"
  }
}
