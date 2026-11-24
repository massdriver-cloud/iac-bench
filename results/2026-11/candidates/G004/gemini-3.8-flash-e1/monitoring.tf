resource "aws_cloudwatch_log_group" "primary_postgresql" {
  name              = "/aws/rds/cluster/${var.name}-primary/postgresql"
  retention_in_days = var.log_retention_in_days

  tags = local.primary_tags
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${var.name}-secondary/postgresql"
  retention_in_days = var.log_retention_in_days

  tags = local.secondary_tags
}

# Cross-region replication lag alarm to protect against write loss / RPO breaches
resource "aws_cloudwatch_metric_alarm" "cross_region_replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${var.name}-cross-region-replication-lag"
  alarm_description   = "Monitors cross-region replication lag for Aurora Global Database ${var.name}. Enforces RPO of seconds."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Maximum"
  threshold           = var.replication_lag_threshold_ms
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  tags = local.secondary_tags
}

# Primary cluster CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "primary_cpu_high" {
  alarm_name          = "${var.name}-primary-cpu-utilization-high"
  alarm_description   = "Monitors CPU utilization for primary Aurora PostgreSQL cluster ${var.name}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }

  tags = local.primary_tags
}

# Secondary cluster CPU utilization alarm
resource "aws_cloudwatch_metric_alarm" "secondary_cpu_high" {
  provider            = aws.secondary
  alarm_name          = "${var.name}-secondary-cpu-utilization-high"
  alarm_description   = "Monitors CPU utilization for secondary Aurora PostgreSQL cluster ${var.name}."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_actions       = var.alarm_actions
  ok_actions          = var.alarm_actions

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  tags = local.secondary_tags
}
