# PostgreSQL logs in CloudWatch, created ahead of the clusters so that
# retention is managed here and not left to RDS defaults (never expire).

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days
}

# Replication lag from the primary to the secondary. This is the number that
# determines how many writes would be lost in a regional failure (RPO).
# The metric is reported on the secondary cluster, so the alarm lives in the
# secondary region. It is missing while the secondary is the writer, which is
# why missing data is not treated as breaching.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider = aws.secondary

  alarm_name          = "${local.secondary_cluster_id}-global-replication-lag"
  alarm_description   = "Aurora Global Database replication lag to ${local.secondary_cluster_id} exceeds 5 seconds for 3 minutes. Writes at risk in a regional failure."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBReplicationLag"
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  threshold           = 5000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"

  dimensions = {
    DBClusterIdentifier = aws_rds_cluster.secondary.id
  }

  alarm_actions = var.secondary_region_alarm_actions
  ok_actions    = var.secondary_region_alarm_actions
}
