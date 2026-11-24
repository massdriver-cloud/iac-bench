# -----------------------------------------------------------------------------
# KMS-Encrypted CloudWatch Log Groups (Primary & Secondary Regions)
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary" {
  for_each = toset(local.log_exports)

  region            = var.primary_region
  name              = "/aws/rds/cluster/${local.primary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.primary_kms_key_arn

  tags = merge(local.tags, {
    Name     = "${local.primary_cluster_id}-${each.value}-logs"
    region   = var.primary_region
    log-type = each.value
  })
}

resource "aws_cloudwatch_log_group" "secondary" {
  for_each = toset(local.log_exports)

  region            = var.secondary_region
  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/${each.value}"
  retention_in_days = var.log_retention_days
  kms_key_id        = local.secondary_kms_key_arn

  tags = merge(local.tags, {
    Name     = "${local.secondary_cluster_id}-${each.value}-logs"
    region   = var.secondary_region
    log-type = each.value
  })
}

# -----------------------------------------------------------------------------
# Cross-Region RPO & Operational Health CloudWatch Alarms
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-global-rpo-lag-high"
  alarm_description   = "Aurora Global Database replication lag for ${var.service_name} (${var.environment}) exceeded ${var.rpo_lag_alarm_threshold_ms}ms, threatening the few-seconds RPO target."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.rpo_lag_alarm_threshold_ms
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = var.alarm_sns_topic_arns.secondary
  ok_actions    = var.alarm_sns_topic_arns.secondary

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-global-rpo-lag-high"
    region = var.secondary_region
  })
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-cpu-high"
  alarm_description   = "Aurora PostgreSQL CPU utilization > 80% on primary cluster ${local.primary_cluster_id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = var.alarm_sns_topic_arns.primary
  ok_actions    = var.alarm_sns_topic_arns.primary

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-cpu-high"
    region = var.primary_region
  })
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-cpu-high"
  alarm_description   = "Aurora PostgreSQL CPU utilization > 80% on secondary cluster ${local.secondary_cluster_id}"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = var.alarm_sns_topic_arns.secondary
  ok_actions    = var.alarm_sns_topic_arns.secondary

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-cpu-high"
    region = var.secondary_region
  })
}

resource "aws_cloudwatch_metric_alarm" "primary_capacity" {
  region              = var.primary_region
  alarm_name          = "${local.primary_cluster_id}-${local.is_serverless ? "acu-utilization-high" : "freeable-memory-low"}"
  alarm_description   = local.is_serverless ? "Aurora Serverless v2 ACU utilization > 85% on ${local.primary_cluster_id}" : "Aurora PostgreSQL freeable memory < 512 MiB on ${local.primary_cluster_id}"
  comparison_operator = local.is_serverless ? "GreaterThanThreshold" : "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = local.is_serverless ? "ACUUtilization" : "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = local.is_serverless ? "Maximum" : "Minimum"
  threshold           = local.is_serverless ? 85 : 536870912
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  alarm_actions = var.alarm_sns_topic_arns.primary
  ok_actions    = var.alarm_sns_topic_arns.primary

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-capacity-alarm"
    region = var.primary_region
  })
}

resource "aws_cloudwatch_metric_alarm" "secondary_capacity" {
  region              = var.secondary_region
  alarm_name          = "${local.secondary_cluster_id}-${local.is_serverless ? "acu-utilization-high" : "freeable-memory-low"}"
  alarm_description   = local.is_serverless ? "Aurora Serverless v2 ACU utilization > 85% on ${local.secondary_cluster_id}" : "Aurora PostgreSQL freeable memory < 512 MiB on ${local.secondary_cluster_id}"
  comparison_operator = local.is_serverless ? "GreaterThanThreshold" : "LessThanThreshold"
  evaluation_periods  = 3
  metric_name         = local.is_serverless ? "ACUUtilization" : "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = local.is_serverless ? "Maximum" : "Minimum"
  threshold           = local.is_serverless ? 85 : 536870912
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = var.alarm_sns_topic_arns.secondary
  ok_actions    = var.alarm_sns_topic_arns.secondary

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-capacity-alarm"
    region = var.secondary_region
  })
}
