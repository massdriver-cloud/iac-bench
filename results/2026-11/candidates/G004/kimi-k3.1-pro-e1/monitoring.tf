resource "aws_sns_topic" "primary_operations" {
  provider = aws.primary

  name              = "${local.base_name}-aurora-primary-operations"
  kms_master_key_id = aws_kms_key.primary.arn

  tags = {
    Purpose = "Aurora operations alarms and RDS events"
  }
}

resource "aws_sns_topic" "secondary_operations" {
  provider = aws.secondary

  name              = "${local.base_name}-aurora-secondary-operations"
  kms_master_key_id = aws_kms_key.secondary.arn

  tags = {
    Purpose = "Aurora operations alarms and RDS events"
  }
}

resource "aws_sns_topic_subscription" "primary_email" {
  provider = aws.primary
  for_each = toset(var.operations_email_endpoints)

  topic_arn = aws_sns_topic.primary_operations.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_sns_topic_subscription" "secondary_email" {
  provider = aws.secondary
  for_each = toset(var.operations_email_endpoints)

  topic_arn = aws_sns_topic.secondary_operations.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  provider = aws.primary
  for_each = { for instance in aws_rds_cluster_instance.primary : instance.identifier => instance }

  alarm_name          = "${local.base_name}-primary-${each.value.identifier}-cpu"
  alarm_description   = "Aurora PostgreSQL instance CPU is above 80 percent."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.primary_operations.arn]
  ok_actions          = [aws_sns_topic.primary_operations.arn]

  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary
  for_each = { for instance in aws_rds_cluster_instance.secondary : instance.identifier => instance }

  alarm_name          = "${local.base_name}-secondary-${each.value.identifier}-cpu"
  alarm_description   = "Aurora PostgreSQL DR instance CPU is above 80 percent."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  metric_name         = "CPUUtilization"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.secondary_operations.arn]
  ok_actions          = [aws_sns_topic.secondary_operations.arn]

  dimensions = {
    DBInstanceIdentifier = each.value.id
  }
}

resource "aws_cloudwatch_metric_alarm" "global_replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.base_name}-global-rpo-lag"
  alarm_description   = "Cross-region Aurora replication lag is approaching the configured managed RPO. Investigate before writes are throttled."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  metric_name         = "AuroraGlobalDBReplicationLag"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = var.global_rpo_milliseconds * 0.8
  unit                = "Milliseconds"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary_operations.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }
}

resource "aws_cloudwatch_metric_alarm" "primary_replica_lag" {
  provider = aws.primary

  alarm_name          = "${local.base_name}-primary-replica-lag"
  alarm_description   = "The slowest in-region Aurora reader is more than one second behind the writer."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 5
  datapoints_to_alarm = 3
  metric_name         = "AuroraReplicaLagMaximum"
  namespace           = "AWS/RDS"
  period              = 60
  statistic           = "Average"
  threshold           = 1000
  unit                = "Milliseconds"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.primary_operations.arn]

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.id
  }
}

resource "aws_db_event_subscription" "primary" {
  provider = aws.primary

  name             = "${local.base_name}-primary-events"
  sns_topic        = aws_sns_topic.primary_operations.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["availability", "failover", "failure", "maintenance"]
  enabled          = true
}

resource "aws_db_event_subscription" "secondary" {
  provider = aws.secondary

  name             = "${local.base_name}-secondary-events"
  sns_topic        = aws_sns_topic.secondary_operations.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["availability", "failover", "failure", "maintenance"]
  enabled          = true
}
