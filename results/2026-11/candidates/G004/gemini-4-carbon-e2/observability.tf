resource "aws_cloudwatch_log_group" "primary" {
  for_each = toset(local.exported_logs)

  region            = var.primary_region
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = local.common_tags
}

resource "aws_cloudwatch_log_group" "secondary" {
  for_each = toset(local.exported_logs)

  region            = var.secondary_region
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_replica_key.secondary.arn

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag"
  alarm_description   = "Cross-region Aurora Global Database replication lag for ${var.service_name} (${var.environment}) exceeded ${var.replication_lag_alarm_threshold_ms}ms, threatening the few-seconds RPO target."
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

  alarm_actions = local.alarm_actions_secondary
  ok_actions    = local.alarm_actions_secondary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Average CPU utilization exceeded 80% on primary Aurora cluster ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = local.alarm_actions_primary
  ok_actions    = local.alarm_actions_primary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-cpu-high"
  alarm_description   = "Average CPU utilization exceeded 80% on secondary Aurora cluster ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = local.alarm_actions_secondary
  ok_actions    = local.alarm_actions_secondary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-freeable-memory-low"
  alarm_description   = "Minimum freeable memory dropped below 512 MiB on primary Aurora cluster ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 536870912
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = local.alarm_actions_primary
  ok_actions    = local.alarm_actions_primary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory_low" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-freeable-memory-low"
  alarm_description   = "Minimum freeable memory dropped below 512 MiB on secondary Aurora cluster ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 536870912
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = local.alarm_actions_secondary
  ok_actions    = local.alarm_actions_secondary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "primary_free_local_storage_low" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-free-local-storage-low"
  alarm_description   = "Minimum free local storage (temp tables/logs) dropped below 5 GiB on primary Aurora cluster ${local.primary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeLocalStorage"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 5368709120
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = local.alarm_actions_primary
  ok_actions    = local.alarm_actions_primary

  tags = local.common_tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_free_local_storage_low" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-free-local-storage-low"
  alarm_description   = "Minimum free local storage (temp tables/logs) dropped below 5 GiB on secondary Aurora cluster ${local.secondary_cluster_id}."
  namespace           = "AWS/RDS"
  metric_name         = "FreeLocalStorage"
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 3
  threshold           = 5368709120
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = local.alarm_actions_secondary
  ok_actions    = local.alarm_actions_secondary

  tags = local.common_tags
}

resource "aws_db_event_subscription" "primary_cluster" {
  count = length(local.alarm_actions_primary) > 0 ? 1 : 0

  region           = var.primary_region
  name             = "${local.primary_cluster_id}-events"
  sns_topic        = local.alarm_actions_primary[0]
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "global-failover", "notification"]

  tags = local.common_tags
}

resource "aws_db_event_subscription" "secondary_cluster" {
  count = length(local.alarm_actions_secondary) > 0 ? 1 : 0

  region           = var.secondary_region
  name             = "${local.secondary_cluster_id}-events"
  sns_topic        = local.alarm_actions_secondary[0]
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "global-failover", "notification"]

  tags = local.common_tags
}
