variable "monitoring_writer" {
  description = "Member currently acting as writer, for alarm routing only. Update after a role reversal, not to initiate one."
  type        = string
  default     = "primary"
  validation {
    condition     = contains(["primary", "secondary"], var.monitoring_writer)
    error_message = "Use primary or secondary, referring to the original member labels."
  }
}

locals {
  workload_connect_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "ConnectOnlyAsApplicationUser"
      Effect = "Allow"
      Action = "rds-db:connect"
      Resource = [
        "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${local.app_db_user}",
        "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${local.app_db_user}",
      ]
    }]
  })
}

resource "aws_iam_policy" "connect" {
  name        = "${local.prefix}-aurora-connect"
  description = "Connect as ${local.app_db_user} in either Aurora region"
  policy      = local.workload_connect_policy
}

resource "aws_iam_role_policy_attachment" "workload" {
  for_each   = var.eks_iam_role_names
  role       = each.key
  policy_arn = aws_iam_policy.connect.arn
}

resource "aws_cloudwatch_metric_alarm" "replication_rpo" {
  for_each = {
    primary   = { region = var.primary_region, cluster = aws_rds_cluster.primary.id }
    secondary = { region = var.secondary_region, cluster = aws_rds_cluster.secondary.id }
  }
  region              = each.value.region
  actions_enabled     = each.key != var.monitoring_writer
  alarm_name          = "${local.prefix}-aurora-global-rpo"
  alarm_description   = "Standby recovery-point lag >= 3 seconds, or telemetry missing. Check cluster health and current writer before considering failover."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = each.value.cluster }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  threshold           = 3000
  comparison_operator = "GreaterThanOrEqualToThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [var.alarm_topic_arns[each.key]]
  ok_actions          = [var.alarm_topic_arns[each.key]]
}

resource "aws_db_event_subscription" "primary" {
  name             = local.primary_id
  sns_topic        = var.alarm_topic_arns.primary
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "maintenance"]
}

resource "aws_db_event_subscription" "secondary" {
  provider         = aws.secondary
  name             = local.secondary_id
  sns_topic        = var.alarm_topic_arns.secondary
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "maintenance"]
}
