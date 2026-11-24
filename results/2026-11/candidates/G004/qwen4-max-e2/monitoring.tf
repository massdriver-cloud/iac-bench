###############################################################################
# Alerting. An SNS topic per region collects database alarms; subscribe your
# paging integration to the output ARNs (or set alert_email for a basic
# subscription). The critical alarm for the DR objective is the global
# database RPO lag in the secondary region: if replication falls behind,
# the "lose at most seconds of writes" guarantee is at risk and someone
# must know before an outage, not during one.
###############################################################################

resource "aws_sns_topic" "alerts_primary" {
  provider = aws.primary

  name = "${local.name}-db-alerts"

  tags = {
    Name = "${local.name}-db-alerts"
  }
}

resource "aws_sns_topic" "alerts_secondary" {
  provider = aws.secondary

  name = "${local.name}-db-alerts"

  tags = {
    Name = "${local.name}-db-alerts"
  }
}

resource "aws_sns_topic_subscription" "email_primary" {
  provider = aws.primary
  count    = var.alert_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alerts_primary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_sns_topic_subscription" "email_secondary" {
  provider = aws.secondary
  count    = var.alert_email != null ? 1 : 0

  topic_arn = aws_sns_topic.alerts_secondary.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

resource "aws_cloudwatch_metric_alarm" "primary_cpu" {
  provider = aws.primary

  alarm_name          = "${local.name}-aurora-primary-high-cpu"
  alarm_description   = "Writer-region CPU sustained above 80% - investigate load or scale instance_class."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alerts_primary.arn]
  ok_actions    = [aws_sns_topic.alerts_primary.arn]

  tags = {
    Name = "${local.name}-aurora-primary-high-cpu"
  }
}

resource "aws_cloudwatch_metric_alarm" "secondary_cpu" {
  provider = aws.secondary

  alarm_name          = "${local.name}-aurora-secondary-high-cpu"
  alarm_description   = "DR-region CPU sustained above 80% - the region must have headroom to absorb production after failover."
  namespace           = "AWS/RDS"
  metric_name         = "CPUUtilization"
  statistic           = "Average"
  period              = 300
  evaluation_periods  = 3
  threshold           = 80
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier
  }

  alarm_actions = [aws_sns_topic.alerts_secondary.arn]
  ok_actions    = [aws_sns_topic.alerts_secondary.arn]

  tags = {
    Name = "${local.name}-aurora-secondary-high-cpu"
  }
}

# Cross-region replication lag (RPO), emitted in the secondary region.
# 10 seconds sustained for 5 minutes means the seconds-level RPO objective
# is in danger.
resource "aws_cloudwatch_metric_alarm" "global_rpo_lag" {
  provider = aws.secondary

  alarm_name          = "${local.name}-aurora-global-rpo-lag"
  alarm_description   = "Aurora Global Database RPO lag > 10s: a regional failover now could lose more than seconds of writes."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  threshold           = 10000 # milliseconds
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  alarm_actions = [aws_sns_topic.alerts_secondary.arn]
  ok_actions    = [aws_sns_topic.alerts_secondary.arn]

  tags = {
    Name = "${local.name}-aurora-global-rpo-lag"
  }
}
