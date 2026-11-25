###############################################################################
# Database logs (connections, DDL and permission changes via pgaudit, errors).
# Created up front so retention and encryption are set before RDS writes.
###############################################################################

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.cluster_ids.primary}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.cluster_ids.secondary}/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

###############################################################################
# Alarms.
#
# Replication lag is the number that matters for the recovery objective: it is
# how much data would be lost if the writer's region vanished right now. The
# metric is reported by whichever cluster is currently the replica, so the
# alarm exists in both regions and stays correct after a failover. (The
# cluster that is currently the writer reports no data, which is not treated
# as a breach.)
###############################################################################

resource "aws_cloudwatch_metric_alarm" "replication_lag_primary" {
  provider = aws.primary

  alarm_name          = "${local.cluster_ids.primary}-global-replication-lag"
  alarm_description   = "Cross-region replication into ${local.cluster_ids.primary} is more than ${var.replication_lag_alarm_seconds}s behind. A regional failover right now would lose more data than the recovery objective allows."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_seconds * 1000 # metric is in milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.alarm_topic_arns.primary
  ok_actions    = var.alarm_topic_arns.primary
}

resource "aws_cloudwatch_metric_alarm" "replication_lag_secondary" {
  provider = aws.secondary

  alarm_name          = "${local.cluster_ids.secondary}-global-replication-lag"
  alarm_description   = "Cross-region replication into ${local.cluster_ids.secondary} is more than ${var.replication_lag_alarm_seconds}s behind. A regional failover right now would lose more data than the recovery objective allows."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.replication_lag_alarm_seconds * 1000 # metric is in milliseconds
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.alarm_topic_arns.secondary
  ok_actions    = var.alarm_topic_arns.secondary
}

resource "aws_cloudwatch_metric_alarm" "cpu_primary" {
  provider = aws.primary

  alarm_name          = "${local.cluster_ids.primary}-cpu-high"
  alarm_description   = "CPU on ${local.cluster_ids.primary} has been above 80% for 15 minutes. Consider a larger instance_class."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = var.alarm_topic_arns.primary
  ok_actions    = var.alarm_topic_arns.primary
}

resource "aws_cloudwatch_metric_alarm" "cpu_secondary" {
  provider = aws.secondary

  alarm_name          = "${local.cluster_ids.secondary}-cpu-high"
  alarm_description   = "CPU on ${local.cluster_ids.secondary} has been above 80% for 15 minutes. Consider a larger instance_class."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  comparison_operator = "GreaterThanThreshold"
  threshold           = 80
  treat_missing_data  = "missing"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = var.alarm_topic_arns.secondary
  ok_actions    = var.alarm_topic_arns.secondary
}
