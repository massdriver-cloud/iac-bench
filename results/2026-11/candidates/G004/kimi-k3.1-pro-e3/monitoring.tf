resource "aws_cloudwatch_metric_alarm" "secondary_global_rpo_lag" {
  provider = aws.secondary

  alarm_name        = "${var.name}-aurora-global-rpo-lag"
  alarm_description = "Aurora global RPO lag has exceeded ${var.rpo_lag_alarm_threshold_seconds} seconds for two minutes. Investigate replication before relying on regional recovery."

  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 2
  threshold           = var.rpo_lag_alarm_threshold_seconds * 1000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  unit                = "Milliseconds"

  alarm_actions = var.secondary_alarm_action_arns
  ok_actions    = var.secondary_alarm_action_arns

  tags = {
    Name = "${var.name}-aurora-global-rpo-lag"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  for_each = aws_rds_cluster_instance.primary

  alarm_name        = "${each.value.identifier}-high-cpu"
  alarm_description = "Aurora instance ${each.value.identifier} has sustained high CPU utilization."

  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  unit                = "Percent"

  alarm_actions = var.primary_alarm_action_arns
  ok_actions    = var.primary_alarm_action_arns

  tags = {
    Name = "${each.value.identifier}-high-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary
  for_each = aws_rds_cluster_instance.secondary

  alarm_name        = "${each.value.identifier}-high-cpu"
  alarm_description = "Aurora instance ${each.value.identifier} has sustained high CPU utilization."

  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = "Average"
  period              = 60
  evaluation_periods  = 5
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "missing"
  unit                = "Percent"

  alarm_actions = var.secondary_alarm_action_arns
  ok_actions    = var.secondary_alarm_action_arns

  tags = {
    Name = "${each.value.identifier}-high-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_freeable_memory" {
  for_each = aws_rds_cluster_instance.primary

  alarm_name        = "${each.value.identifier}-low-freeable-memory"
  alarm_description = "Aurora instance ${each.value.identifier} has less than 256 MiB of freeable memory."

  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  unit                = "Bytes"

  alarm_actions = var.primary_alarm_action_arns
  ok_actions    = var.primary_alarm_action_arns

  tags = {
    Name = "${each.value.identifier}-low-freeable-memory"
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_freeable_memory" {
  provider = aws.secondary
  for_each = aws_rds_cluster_instance.secondary

  alarm_name        = "${each.value.identifier}-low-freeable-memory"
  alarm_description = "Aurora instance ${each.value.identifier} has less than 256 MiB of freeable memory."

  namespace           = "AWS/RDS"
  metric_name         = "FreeableMemory"
  dimensions          = { DBInstanceIdentifier = each.value.identifier }
  statistic           = "Minimum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 268435456
  comparison_operator = "LessThanThreshold"
  treat_missing_data  = "missing"
  unit                = "Bytes"

  alarm_actions = var.secondary_alarm_action_arns
  ok_actions    = var.secondary_alarm_action_arns

  tags = {
    Name = "${each.value.identifier}-low-freeable-memory"
  }
}
