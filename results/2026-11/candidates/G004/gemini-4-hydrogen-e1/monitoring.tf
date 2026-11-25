resource "aws_sns_topic" "primary" {
  count = var.primary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.name_prefix}-aurora-alerts"
  kms_master_key_id = aws_kms_key.primary.arn
}

resource "aws_sns_topic" "secondary" {
  provider = aws.secondary
  count    = var.secondary_alarm_sns_topic_arn == null ? 1 : 0

  name              = "${local.name_prefix}-aurora-alerts"
  kms_master_key_id = aws_kms_key.secondary.arn
}

resource "aws_db_event_subscription" "primary_cluster" {
  name        = "${local.name_prefix}-primary-cluster-events"
  sns_topic   = local.primary_sns_topic_arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.primary.id]

  event_categories = [
    "failover",
    "failure",
    "maintenance",
    "notification",
  ]
}

resource "aws_db_event_subscription" "primary_instances" {
  name        = "${local.name_prefix}-primary-instance-events"
  sns_topic   = local.primary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.primary[*].id

  event_categories = [
    "availability",
    "failover",
    "failure",
    "low storage",
    "recovery",
  ]
}

resource "aws_db_event_subscription" "secondary_cluster" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary-cluster-events"
  sns_topic   = local.secondary_sns_topic_arn
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.secondary.id]

  event_categories = [
    "failover",
    "failure",
    "maintenance",
    "notification",
  ]
}

resource "aws_db_event_subscription" "secondary_instances" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary-instance-events"
  sns_topic   = local.secondary_sns_topic_arn
  source_type = "db-instance"
  source_ids  = aws_rds_cluster_instance.secondary[*].id

  event_categories = [
    "availability",
    "failover",
    "failure",
    "low storage",
    "recovery",
  ]
}

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-global-replication-lag"
  alarm_description   = "Cross-region Aurora Global DB replication lag exceeds ${var.replication_lag_alarm_threshold_ms}ms RPO target."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.replication_lag_alarm_threshold_ms
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  alarm_name          = "${local.name_prefix}-primary-high-cpu"
  alarm_description   = "Primary Aurora cluster CPU utilization exceeds ${var.cpu_alarm_threshold_percent}%."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-secondary-high-cpu"
  alarm_description   = "Secondary Aurora cluster CPU utilization exceeds ${var.cpu_alarm_threshold_percent}%."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.cpu_alarm_threshold_percent
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  count = local.primary_is_serverless ? 0 : 1

  alarm_name          = "${local.name_prefix}-primary-low-memory"
  alarm_description   = "Primary Aurora cluster FreeableMemory dropped below ${var.freeable_memory_alarm_threshold_bytes} bytes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.freeable_memory_alarm_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = [local.primary_sns_topic_arn]
  ok_actions    = [local.primary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory" {
  provider = aws.secondary
  count    = local.secondary_is_serverless ? 0 : 1

  alarm_name          = "${local.name_prefix}-secondary-low-memory"
  alarm_description   = "Secondary Aurora cluster FreeableMemory dropped below ${var.freeable_memory_alarm_threshold_bytes} bytes."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 300
  evaluation_periods  = 3
  threshold           = var.freeable_memory_alarm_threshold_bytes
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = [local.secondary_sns_topic_arn]
  ok_actions    = [local.secondary_sns_topic_arn]
}

resource "aws_cloudwatch_metric_alarm" "primary_deadlocks" {
  alarm_name          = "${local.name_prefix}-primary-deadlocks"
  alarm_description   = "PostgreSQL deadlocks detected on primary Aurora cluster."
  namespace           = "AWS/RDS"
  metric_name         = "Deadlocks"
  statistic           = "Sum"
  period              = 300
  evaluation_periods  = 1
  threshold           = 0
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = [local.primary_sns_topic_arn]
}
