resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${local.name_prefix}-primary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = {
    Name = "${local.name_prefix}-primary-postgresql-logs"
    Role = "primary"
  }
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.name_prefix}-secondary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = {
    Name = "${local.name_prefix}-secondary-postgresql-logs"
    Role = "secondary"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  alarm_name          = "${local.name_prefix}-primary-cpu-high"
  alarm_description   = "Primary Aurora PostgreSQL cluster CPU utilization exceeded 80%."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.primary_alarm_sns_topic_arns
  ok_actions    = var.primary_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory_low" {
  alarm_name          = "${local.name_prefix}-primary-freeable-memory-low"
  alarm_description   = "Primary Aurora PostgreSQL cluster average freeable memory dropped below 512 MiB."
  comparison_operator = "LessThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "FreeableMemory"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 536870912
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.primary_alarm_sns_topic_arns
  ok_actions    = var.primary_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "primary_deadlocks" {
  alarm_name          = "${local.name_prefix}-primary-deadlocks"
  alarm_description   = "Deadlocks detected on primary Aurora PostgreSQL cluster."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "Deadlocks"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Sum"
  threshold           = 1
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.primary_alarm_sns_topic_arns
  ok_actions    = var.primary_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "secondary_global_rpo_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-secondary-global-rpo-lag"
  alarm_description   = "Aurora Global Database RPO lag exceeded ${var.global_rpo_lag_alarm_threshold_ms} ms between ${var.primary_region} and ${var.secondary_region}."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBRPOLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.global_rpo_lag_alarm_threshold_ms
  treat_missing_data  = "breaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.secondary_alarm_sns_topic_arns
  ok_actions    = var.secondary_alarm_sns_topic_arns
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider = aws.secondary

  alarm_name          = "${local.name_prefix}-secondary-cpu-high"
  alarm_description   = "Secondary Aurora PostgreSQL cluster CPU utilization exceeded 80%."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.secondary_alarm_sns_topic_arns
  ok_actions    = var.secondary_alarm_sns_topic_arns
}
