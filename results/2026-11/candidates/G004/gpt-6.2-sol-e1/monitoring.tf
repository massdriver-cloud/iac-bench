resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.name}-${var.regions.primary}/postgresql"
  retention_in_days = 90
  tags              = local.tags
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name}-${var.regions.secondary}/postgresql"
  retention_in_days = 90
  tags              = local.tags
}

# Create local alarm destinations unless an existing regional pager topic is supplied.
resource "aws_sns_topic" "primary" {
  count = var.incident_topic_arns.primary == null ? 1 : 0
  name  = "${local.name}-aurora-incidents"
  tags  = local.tags
}

resource "aws_sns_topic" "secondary" {
  provider = aws.secondary
  count    = var.incident_topic_arns.secondary == null ? 1 : 0
  name     = "${local.name}-aurora-incidents"
  tags     = local.tags
}

locals {
  primary_topic         = var.incident_topic_arns.primary == null ? aws_sns_topic.primary[0].arn : var.incident_topic_arns.primary
  secondary_topic       = var.incident_topic_arns.secondary == null ? aws_sns_topic.secondary[0].arn : var.incident_topic_arns.secondary
  lag_alarm_description = "Potential data loss exceeds the 3-second DR target. This metric normally exists only on the current secondary; monitor missing recovery telemetry and service health separately."
}

resource "aws_cloudwatch_metric_alarm" "primary_rpo" {
  alarm_name          = "${local.name}-aurora-rpo-lag"
  alarm_description   = local.lag_alarm_description
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.primary.cluster_identifier }
  alarm_actions       = [local.primary_topic]
  ok_actions          = [local.primary_topic]
  tags                = local.tags
}

resource "aws_cloudwatch_metric_alarm" "secondary_rpo" {
  provider            = aws.secondary
  alarm_name          = "${local.name}-aurora-rpo-lag"
  alarm_description   = local.lag_alarm_description
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 3000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "notBreaching"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.cluster_identifier }
  alarm_actions       = [local.secondary_topic]
  ok_actions          = [local.secondary_topic]
  tags                = local.tags
}

resource "aws_db_event_subscription" "primary" {
  name             = "${local.name}-aurora-events"
  sns_topic        = local.primary_topic
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "maintenance"]
  tags             = local.tags
  depends_on       = [aws_sns_topic_policy.primary]
}

resource "aws_db_event_subscription" "secondary" {
  provider         = aws.secondary
  name             = "${local.name}-aurora-events"
  sns_topic        = local.secondary_topic
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "maintenance"]
  tags             = local.tags
  depends_on       = [aws_sns_topic_policy.secondary]
}
