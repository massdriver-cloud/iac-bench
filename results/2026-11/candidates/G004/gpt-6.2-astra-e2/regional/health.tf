data "aws_subnet" "db" {
  for_each = toset(data.aws_subnets.db.ids)
  id       = each.key
}
locals {
  zones = sort(distinct([for s in data.aws_subnet.db : s.availability_zone]))
}
output "ready_global_id" {
  value      = aws_rds_cluster.db.global_cluster_identifier
  depends_on = [aws_rds_cluster_instance.db]
}
resource "aws_cloudwatch_metric_alarm" "lag" {
  count               = var.primary ? 0 : 1
  alarm_name          = "${var.name}-global-rpo"
  alarm_description   = "Secondary RPO lag exceeded three seconds or replication telemetry is missing. Investigate before promotion."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.db.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 3000
  treat_missing_data  = "breaching"
  alarm_actions       = [var.topic]
  ok_actions          = [var.topic]
  tags                = var.tags
}
resource "aws_db_event_subscription" "cluster" {
  name        = "${var.name}-cluster-events"
  sns_topic   = var.topic
  source_type = "db-cluster"
  source_ids  = [aws_rds_cluster.db.id]
  tags        = var.tags
}
