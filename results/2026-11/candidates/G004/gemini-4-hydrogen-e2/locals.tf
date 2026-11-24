locals {
  is_prod     = var.environment == "prod"
  name_prefix = "${var.service_name}-${var.environment}"
  vpc_name    = "apps-${var.environment}"

  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_db_users  = length(var.iam_db_users) > 0 ? var.iam_db_users : [local.database_name]

  primary_instance_count              = coalesce(var.primary_instance_count, local.is_prod ? 2 : 1)
  secondary_instance_count            = coalesce(var.secondary_instance_count, local.is_prod ? 2 : 1)
  backup_retention_period             = coalesce(var.backup_retention_period, local.is_prod ? 35 : 14)
  performance_insights_retention_days = coalesce(var.performance_insights_retention_period, local.is_prod ? 93 : 7)
  log_retention_in_days               = coalesce(var.log_retention_in_days, local.is_prod ? 365 : 90)

  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family

  default_cluster_parameters = {
    "rds.force_ssl" = {
      value        = "1"
      apply_method = "immediate"
    }
    "password_encryption" = {
      value        = "scram-sha-256"
      apply_method = "immediate"
    }
    "shared_preload_libraries" = {
      value        = "pgaudit,pg_stat_statements"
      apply_method = "pending-reboot"
    }
    "pgaudit.log" = {
      value        = var.pgaudit_log
      apply_method = "immediate"
    }
    "log_connections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_disconnections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_lock_waits" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_min_duration_statement" = {
      value        = var.slow_query_log_threshold_ms
      apply_method = "immediate"
    }
    "statement_timeout" = {
      value        = var.statement_timeout_ms
      apply_method = "immediate"
    }
    "idle_in_transaction_session_timeout" = {
      value        = var.idle_in_transaction_session_timeout_ms
      apply_method = "immediate"
    }
  }

  cluster_parameters = merge(local.default_cluster_parameters, var.extra_cluster_parameters)

  primary_alarm_topic_arn   = coalesce(var.primary_alarm_sns_topic_arn, try(aws_sns_topic.alarms_primary[0].arn, ""))
  secondary_alarm_topic_arn = coalesce(var.secondary_alarm_sns_topic_arn, try(aws_sns_topic.alarms_secondary[0].arn, ""))

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      ManagedBy          = "opentofu"
      DataClassification = "confidential-payment"
    },
    var.tags
  )
}
