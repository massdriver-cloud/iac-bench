resource "aws_iam_role" "monitoring" {
  name = "${local.prefix}-monitoring"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole", Principal = { Service = "monitoring.rds.amazonaws.com" }
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
locals {
  connect_resources = {
    for user, config in var.database_users : user => [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"
    ]
  }
  logs_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AccountAdministration", Effect = "Allow", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
      {
        Sid       = "CloudWatchLogs", Effect = "Allow"
        Principal = { Service = ["logs.${var.primary_region}.amazonaws.com", "logs.${var.secondary_region}.amazonaws.com"] }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = { ArnLike = { "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.current.partition}:logs:*:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.prefix}-*" } }
      }
    ]
  })
  alert_key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Sid = "AccountAdministration", Effect = "Allow", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "kms:*", Resource = "*" },
      {
        Sid       = "AlertPublishers", Effect = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.rds.amazonaws.com", "rds.amazonaws.com"] }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"], Resource = "*"
      }
    ]
  })
}
resource "aws_iam_role_policy" "primary_connect" {
  for_each = var.database_users
  name     = "${local.prefix}-${each.key}-primary-connect"
  role     = each.value.primary_role_name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = local.connect_resources[each.key] }]
  })
}
resource "aws_iam_role_policy" "secondary_connect" {
  for_each = var.database_users
  name     = "${local.prefix}-${each.key}-secondary-connect"
  role     = each.value.secondary_role_name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = "rds-db:connect", Resource = local.connect_resources[each.key] }]
  })
}
resource "aws_kms_key" "logs_primary" {
  description             = "${local.prefix} primary PostgreSQL audit log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.logs_key_policy
}
resource "aws_kms_key" "logs_secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} secondary PostgreSQL audit log encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.logs_key_policy
}
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.prefix}-primary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs_primary.arn
  skip_destroy      = true
}
resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.prefix}-secondary/postgresql"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.logs_secondary.arn
  skip_destroy      = true
}
resource "aws_kms_key" "alerts_primary" {
  description             = "${local.prefix} primary alarm notification encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.alert_key_policy
}
resource "aws_kms_key" "alerts_secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} secondary alarm notification encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.alert_key_policy
}
resource "aws_sns_topic" "primary" {
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.alerts_primary.arn
}
resource "aws_sns_topic" "secondary" {
  provider          = aws.secondary
  name              = "${local.prefix}-database-alerts"
  kms_master_key_id = aws_kms_key.alerts_secondary.arn
}
locals {
  alert_topic_policy = {
    for name, arn in { primary = aws_sns_topic.primary.arn, secondary = aws_sns_topic.secondary.arn } : name => jsonencode({
      Version = "2012-10-17"
      Statement = [
        { Effect = "Allow", Principal = { AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root" }, Action = "sns:*", Resource = arn },
        {
          Effect    = "Allow", Principal = { Service = ["cloudwatch.amazonaws.com", "events.rds.amazonaws.com", "rds.amazonaws.com"] }
          Action    = "sns:Publish", Resource = arn
          Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
        }
      ]
    })
  }
}
resource "aws_sns_topic_policy" "primary" {
  arn    = aws_sns_topic.primary.arn
  policy = local.alert_topic_policy.primary
}
resource "aws_sns_topic_policy" "secondary" {
  provider = aws.secondary
  arn      = aws_sns_topic.secondary.arn
  policy   = local.alert_topic_policy.secondary
}
resource "aws_sns_topic_subscription" "primary" {
  topic_arn = aws_sns_topic.primary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
resource "aws_sns_topic_subscription" "secondary" {
  provider  = aws.secondary
  topic_arn = aws_sns_topic.secondary.arn
  protocol  = "email"
  endpoint  = var.alarm_email
}
# Aurora PostgreSQL's RPO lag includes durability, rather than just transport lag.
resource "aws_cloudwatch_metric_alarm" "replication_lag" {
  provider            = aws.secondary
  alarm_name          = "${local.prefix}-cross-region-rpo-at-risk"
  alarm_description   = "Global RPO lag exceeds 2 seconds. Investigate now; async replication cannot guarantee a hard RPO. Missing data also pages."
  namespace           = "AWS/RDS"
  metric_name         = "AuroraGlobalDBRPOLag"
  dimensions          = { DBClusterIdentifier = aws_rds_cluster.secondary.id }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  threshold           = 2000
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
locals {
  instance_alarms = {
    cpu    = { metric = "CPUUtilization", comparison = "GreaterThanThreshold", threshold = 80, statistic = "Average" }
    memory = { metric = "FreeableMemory", comparison = "LessThanThreshold", threshold = 1073741824, statistic = "Minimum" }
  }
  alarm_matrix = { for pair in setproduct([0, 1], keys(local.instance_alarms)) : "${pair[0]}-${pair[1]}" => { index = pair[0], kind = pair[1] } }
}
resource "aws_cloudwatch_metric_alarm" "primary_instance" {
  for_each            = local.alarm_matrix
  alarm_name          = "${local.prefix}-primary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = local.instance_alarms[each.value.kind].metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.primary[each.value.index].id }
  statistic           = local.instance_alarms[each.value.kind].statistic
  period              = 60
  evaluation_periods  = 5
  threshold           = local.instance_alarms[each.value.kind].threshold
  comparison_operator = local.instance_alarms[each.value.kind].comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.primary.arn]
  ok_actions          = [aws_sns_topic.primary.arn]
}
resource "aws_cloudwatch_metric_alarm" "secondary_instance" {
  provider            = aws.secondary
  for_each            = local.alarm_matrix
  alarm_name          = "${local.prefix}-secondary-${each.key}"
  namespace           = "AWS/RDS"
  metric_name         = local.instance_alarms[each.value.kind].metric
  dimensions          = { DBInstanceIdentifier = aws_rds_cluster_instance.secondary[each.value.index].id }
  statistic           = local.instance_alarms[each.value.kind].statistic
  period              = 60
  evaluation_periods  = 5
  threshold           = local.instance_alarms[each.value.kind].threshold
  comparison_operator = local.instance_alarms[each.value.kind].comparison
  treat_missing_data  = "breaching"
  alarm_actions       = [aws_sns_topic.secondary.arn]
  ok_actions          = [aws_sns_topic.secondary.arn]
}
resource "aws_db_event_subscription" "primary" {
  name             = "${local.prefix}-primary-events"
  sns_topic        = aws_sns_topic.primary.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.primary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
  depends_on       = [aws_sns_topic_policy.primary]
}
resource "aws_db_event_subscription" "secondary" {
  provider         = aws.secondary
  name             = "${local.prefix}-secondary-events"
  sns_topic        = aws_sns_topic.secondary.arn
  source_type      = "db-cluster"
  source_ids       = [aws_rds_cluster.secondary.id]
  event_categories = ["failover", "failure", "maintenance", "notification"]
  depends_on       = [aws_sns_topic_policy.secondary]
}
