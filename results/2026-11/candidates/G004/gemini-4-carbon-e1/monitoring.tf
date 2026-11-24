# -----------------------------------------------------------------------------
# Regional Encrypted Alerting SNS Topics & Policies
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "primary_alerts" {
  region            = var.primary_region
  name              = "${local.primary_cluster_id}-db-alerts"
  kms_master_key_id = aws_kms_key.primary.arn

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-db-alerts"
  })
}

data "aws_iam_policy_document" "primary_sns_policy" {
  statement {
    sid     = "AllowCloudWatchAndRDSEventsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [
      aws_sns_topic.primary_alerts.arn,
    ]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.rds.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid     = "EnforceTLSForSNSTopic"
    effect  = "Deny"
    actions = ["sns:Publish"]
    resources = [
      aws_sns_topic.primary_alerts.arn,
    ]

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
}

resource "aws_sns_topic_policy" "primary_alerts" {
  region = var.primary_region
  arn    = aws_sns_topic.primary_alerts.arn
  policy = data.aws_iam_policy_document.primary_sns_policy.json
}

resource "aws_sns_topic" "secondary_alerts" {
  region            = var.secondary_region
  name              = "${local.secondary_cluster_id}-db-alerts"
  kms_master_key_id = aws_kms_key.secondary.arn

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-db-alerts"
  })
}

data "aws_iam_policy_document" "secondary_sns_policy" {
  statement {
    sid     = "AllowCloudWatchAndRDSEventsPublish"
    effect  = "Allow"
    actions = ["sns:Publish"]
    resources = [
      aws_sns_topic.secondary_alerts.arn,
    ]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.rds.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  statement {
    sid     = "EnforceTLSForSNSTopic"
    effect  = "Deny"
    actions = ["sns:Publish"]
    resources = [
      aws_sns_topic.secondary_alerts.arn,
    ]

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
}

resource "aws_sns_topic_policy" "secondary_alerts" {
  region = var.secondary_region
  arn    = aws_sns_topic.secondary_alerts.arn
  policy = data.aws_iam_policy_document.secondary_sns_policy.json
}

locals {
  primary_alarm_actions   = distinct(concat([aws_sns_topic.primary_alerts.arn], var.alarm_sns_topic_arns.primary))
  secondary_alarm_actions = distinct(concat([aws_sns_topic.secondary_alerts.arn], var.alarm_sns_topic_arns.secondary))
}

# -----------------------------------------------------------------------------
# RDS Cluster & Instance Event Subscriptions (Both Regions)
# -----------------------------------------------------------------------------

resource "aws_db_event_subscription" "primary_cluster" {
  region           = var.primary_region
  name             = "${local.primary_cluster_id}-cluster-events"
  sns_topic        = aws_sns_topic.primary_alerts.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "notification"]

  tags = local.tags
}

resource "aws_db_event_subscription" "primary_instances" {
  region      = var.primary_region
  name        = "${local.primary_cluster_id}-instance-events"
  sns_topic   = aws_sns_topic.primary_alerts.arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.primary[*].id
  event_categories = [
    "availability",
    "configuration change",
    "failover",
    "failure",
    "maintenance",
    "recovery",
    "security",
  ]

  tags = local.tags
}

resource "aws_db_event_subscription" "secondary_cluster" {
  region           = var.secondary_region
  name             = "${local.secondary_cluster_id}-cluster-events"
  sns_topic        = aws_sns_topic.secondary_alerts.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "notification"]

  tags = local.tags
}

resource "aws_db_event_subscription" "secondary_instances" {
  region      = var.secondary_region
  name        = "${local.secondary_cluster_id}-instance-events"
  sns_topic   = aws_sns_topic.secondary_alerts.arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.secondary[*].id
  event_categories = [
    "availability",
    "configuration change",
    "failover",
    "failure",
    "maintenance",
    "recovery",
    "security",
  ]

  tags = local.tags
}

# -----------------------------------------------------------------------------
# CloudWatch Alarms (RPO Guard, CPU, Memory, ACU, Replica Lag, Deadlocks)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-global-rpo-lag-high"
  alarm_description   = "Cross-region AuroraGlobalDBReplicationLag for ${var.service_name} (${local.env_short}) exceeded ${var.rpo_replication_lag_alarm_ms} ms, risking the few-seconds RPO target."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = var.rpo_replication_lag_alarm_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions
  ok_actions    = local.secondary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Average CPU utilization on ${local.primary_cluster_id} exceeded 80% for 5 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = local.primary_alarm_actions
  ok_actions    = local.primary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-cpu-high"
  alarm_description   = "Average CPU utilization on ${local.secondary_cluster_id} exceeded 80% for 5 minutes."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions
  ok_actions    = local.secondary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-freeable-memory-low"
  alarm_description   = "Minimum FreeableMemory on ${local.primary_cluster_id} fell below 512 MiB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 536870912
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = local.primary_alarm_actions
  ok_actions    = local.primary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory_low" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-freeable-memory-low"
  alarm_description   = "Minimum FreeableMemory on ${local.secondary_cluster_id} fell below 512 MiB."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 536870912
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions
  ok_actions    = local.secondary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_acu_utilization_high" {
  count = local.is_serverless ? 1 : 0

  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-acu-utilization-high"
  alarm_description   = "Serverless v2 ACUUtilization on ${local.primary_cluster_id} exceeded 85% of max_capacity."
  namespace           = "AWS/RDS"
  metric_name         = "ACUUtilization"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = local.primary_alarm_actions
  ok_actions    = local.primary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_acu_utilization_high" {
  count = local.is_serverless ? 1 : 0

  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-acu-utilization-high"
  alarm_description   = "Serverless v2 ACUUtilization on ${local.secondary_cluster_id} exceeded 85% of max_capacity."
  namespace           = "AWS/RDS"
  metric_name         = "ACUUtilization"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 85
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions
  ok_actions    = local.secondary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_replica_lag_high" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-replica-lag-high"
  alarm_description   = "Intra-region Multi-AZ AuroraReplicaLag on ${local.primary_cluster_id} exceeded 1000 ms."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = local.primary_alarm_actions
  ok_actions    = local.primary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_replica_lag_high" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-replica-lag-high"
  alarm_description   = "Intra-region Multi-AZ AuroraReplicaLag on ${local.secondary_cluster_id} exceeded 1000 ms."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraReplicaLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  threshold           = 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions
  ok_actions    = local.secondary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "primary_deadlocks" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-deadlocks"
  alarm_description   = "Database deadlocks detected on ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = local.primary_alarm_actions

  tags = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_deadlocks" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-deadlocks"
  alarm_description   = "Database deadlocks detected on ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 2
  datapoints_to_alarm = 2
  threshold           = 1
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = local.secondary_alarm_actions

  tags = local.tags
}
