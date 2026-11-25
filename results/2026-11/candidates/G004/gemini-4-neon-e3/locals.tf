locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition

  name_prefix              = "${var.service_name}-${var.environment}"
  primary_cluster_id       = "${local.name_prefix}-${var.primary_region}"
  secondary_cluster_id     = "${local.name_prefix}-${var.secondary_region}"
  database_name            = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  secondary_instance_class = coalesce(var.secondary_instance_class, var.instance_class)
  iam_auth_db_users        = length(var.iam_auth_db_users) > 0 ? var.iam_auth_db_users : [local.database_name]

  primary_azs   = distinct(sort([for s in data.aws_subnet.primary_database : s.availability_zone]))
  secondary_azs = distinct(sort([for s in data.aws_subnet.secondary_database : s.availability_zone]))

  primary_parameter_group_family   = data.aws_rds_engine_version.primary.parameter_group_family
  secondary_parameter_group_family = data.aws_rds_engine_version.secondary.parameter_group_family

  common_tags = merge(
    {
      service             = var.service_name
      environment         = var.environment
      data-classification = var.data_classification
      managed-by          = "opentofu"
      component           = "aurora-postgresql-global"
    },
    var.tags
  )

  # ----------------------------------------------------------------------------
  # Shared PostgreSQL DBA-grade parameter defaults (applied identically in both regions)
  # ----------------------------------------------------------------------------
  default_cluster_parameters = {
    # Enforce encrypted TLS 1.2+ transport for all client connections
    "rds.force_ssl" = {
      value        = "1"
      apply_method = "pending-reboot"
    }
    "ssl_min_protocol_version" = {
      value        = "TLSv1.2"
      apply_method = "immediate"
    }

    # Audit & query observability extensions
    "shared_preload_libraries" = {
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    }
    "pgaudit.log" = {
      value        = var.pgaudit_log_classes
      apply_method = "immediate"
    }
    "pgaudit.log_catalog" = {
      value        = "0"
      apply_method = "immediate"
    }
    # Never log bind parameters so customer PII and payment tokens cannot leak into logs
    "pgaudit.log_parameter" = {
      value        = "0"
      apply_method = "immediate"
    }

    # Connection, slow query, lock, and temp-file diagnostics
    "log_connections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_disconnections" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_min_duration_statement" = {
      value        = tostring(var.slow_query_log_threshold_ms)
      apply_method = "immediate"
    }
    "log_lock_waits" = {
      value        = "1"
      apply_method = "immediate"
    }
    "deadlock_timeout" = {
      value        = "1000"
      apply_method = "immediate"
    }
    "log_temp_files" = {
      value        = "10240"
      apply_method = "immediate"
    }

    # Guard against abandoned transactions from crashed EKS pods blocking vacuum/locks
    "idle_in_transaction_session_timeout" = {
      value        = tostring(var.idle_in_transaction_session_timeout_ms)
      apply_method = "immediate"
    }

    # Query statistics for tuning
    "pg_stat_statements.track" = {
      value        = "all"
      apply_method = "immediate"
    }
    "pg_stat_statements.max" = {
      value        = "10000"
      apply_method = "pending-reboot"
    }
  }

  cluster_parameters = merge(
    local.default_cluster_parameters,
    { for p in var.extra_cluster_parameters : p.name => {
      value        = p.value
      apply_method = p.apply_method
    } }
  )

  default_instance_parameters = {
    # Aurora SSD-backed storage favors index scans over sequential scans (default 4.0 assumes spinning disks)
    "random_page_cost" = {
      value        = "1.1"
      apply_method = "immediate"
    }
    # Log slow autovacuum runs to catch table bloat early
    "log_autovacuum_min_duration" = {
      value        = "1000"
      apply_method = "immediate"
    }
  }

  instance_parameters = merge(
    local.default_instance_parameters,
    { for p in var.extra_instance_parameters : p.name => {
      value        = p.value
      apply_method = p.apply_method
    } }
  )
}
