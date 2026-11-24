locals {
  is_prod     = var.environment == "prod"
  name_prefix = "${var.service_name}-${var.environment}"
  vpc_name    = "apps-${var.environment}"

  database_name     = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_auth_db_users = coalesce(var.iam_auth_db_users, [local.database_name])

  instance_class           = coalesce(var.instance_class, local.is_prod ? "db.r6g.large" : "db.serverless")
  secondary_instance_class = coalesce(var.secondary_instance_class, local.instance_class)

  primary_is_serverless   = local.instance_class == "db.serverless"
  secondary_is_serverless = local.secondary_instance_class == "db.serverless"

  backup_retention_period             = coalesce(var.backup_retention_period, local.is_prod ? 35 : 7)
  deletion_protection                 = var.deletion_protection != null ? var.deletion_protection : local.is_prod
  skip_final_snapshot                 = var.skip_final_snapshot != null ? var.skip_final_snapshot : !local.is_prod
  apply_immediately                   = var.apply_immediately != null ? var.apply_immediately : !local.is_prod
  performance_insights_retention_days = coalesce(var.performance_insights_retention_days, local.is_prod ? 31 : 7)
  log_retention_days                  = coalesce(var.log_retention_days, local.is_prod ? 365 : 30)

  primary_allowed_cidrs   = concat(var.primary_allowed_cidr_blocks, var.allow_vpc_cidr ? [data.aws_vpc.primary.cidr_block] : [])
  secondary_allowed_cidrs = concat(var.secondary_allowed_cidr_blocks, var.allow_vpc_cidr ? [data.aws_vpc.secondary.cidr_block] : [])

  primary_sns_topic_arn   = var.primary_alarm_sns_topic_arn != null ? var.primary_alarm_sns_topic_arn : aws_sns_topic.primary[0].arn
  secondary_sns_topic_arn = var.secondary_alarm_sns_topic_arn != null ? var.secondary_alarm_sns_topic_arn : aws_sns_topic.secondary[0].arn

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      ManagedBy          = "opentofu"
      DataClassification = "restricted"
    },
    var.tags
  )
}
