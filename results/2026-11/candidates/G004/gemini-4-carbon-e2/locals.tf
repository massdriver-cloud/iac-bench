data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

data "aws_rds_engine_version" "primary" {
  region  = var.primary_region
  engine  = "aurora-postgresql"
  version = coalesce(var.engine_version, var.engine_major_version)
  latest  = true

  lifecycle {
    postcondition {
      condition     = self.supports_global_databases
      error_message = "Selected Aurora PostgreSQL version ${self.version_actual} in ${var.primary_region} does not support Aurora Global Databases."
    }
  }
}

data "aws_rds_engine_version" "secondary" {
  region  = var.secondary_region
  engine  = "aurora-postgresql"
  version = data.aws_rds_engine_version.primary.version_actual
  latest  = true

  lifecycle {
    postcondition {
      condition     = self.supports_global_databases && self.version_actual == data.aws_rds_engine_version.primary.version_actual
      error_message = "Aurora PostgreSQL version ${data.aws_rds_engine_version.primary.version_actual} must be available and support Global Databases in ${var.secondary_region}."
    }
  }
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  name_prefix          = "${var.service_name}-${var.environment}"
  global_cluster_id    = "${local.name_prefix}-global"
  primary_cluster_id   = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id = "${local.name_prefix}-${var.secondary_region}"
  vpc_name             = "apps-${var.environment}"

  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  iam_db_users  = length(var.iam_database_users) > 0 ? var.iam_database_users : toset([local.database_name])

  engine_version         = data.aws_rds_engine_version.primary.version_actual
  parameter_group_family = data.aws_rds_engine_version.primary.parameter_group_family

  is_serverless           = var.instance_class == "db.serverless"
  enable_read_autoscaling = var.enable_read_autoscaling && !local.is_serverless
  ca_cert_identifier      = "rds-ca-ecc384-g1"

  exported_logs = ["postgresql", "iam-db-auth-error", "instance"]

  # Stagger backup and maintenance windows across off-peak US hours and separate days
  # so maintenance never affects primary and secondary regions simultaneously.
  primary_backup_window        = "06:00-07:00"
  secondary_backup_window      = "08:00-09:00"
  primary_maintenance_window   = "sun:07:30-sun:08:30"
  secondary_maintenance_window = "wed:09:30-wed:10:30"

  baseline_cluster_parameters = [
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "pending-reboot"
    },
    {
      name         = "password_encryption"
      value        = "scram-sha-256"
      apply_method = "immediate"
    },
    {
      name         = "shared_preload_libraries"
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    },
    {
      name         = "pgaudit.log"
      value        = "ddl,role"
      apply_method = "immediate"
    },
    {
      name         = "pg_stat_statements.track"
      value        = "all"
      apply_method = "immediate"
    },
    {
      name         = "log_connections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_disconnections"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_lock_waits"
      value        = "1"
      apply_method = "immediate"
    },
    {
      name         = "log_min_duration_statement"
      value        = tostring(var.slow_query_log_threshold_ms)
      apply_method = "immediate"
    },
    {
      name         = "idle_in_transaction_session_timeout"
      value        = tostring(var.idle_in_transaction_timeout_ms)
      apply_method = "immediate"
    },
  ]

  override_param_names = toset([for p in var.additional_cluster_parameters : lower(p.name)])

  effective_cluster_parameters = concat(
    [for p in local.baseline_cluster_parameters : p if !contains(local.override_param_names, lower(p.name))],
    var.additional_cluster_parameters
  )

  alarm_actions_primary   = coalesce(var.alarm_sns_topic_arns.primary, [])
  alarm_actions_secondary = coalesce(var.alarm_sns_topic_arns.secondary, [])

  common_tags = merge(
    var.tags,
    {
      service             = var.service_name
      environment         = var.environment
      managed-by          = "opentofu"
      data-classification = "customer-payment-restricted"
    }
  )
}
