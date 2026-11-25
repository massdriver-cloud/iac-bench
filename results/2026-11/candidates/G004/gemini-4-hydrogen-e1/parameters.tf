locals {
  cluster_parameters = [
    {
      name         = "rds.force_ssl"
      value        = "1"
      apply_method = "pending-reboot"
    },
    {
      name         = "shared_preload_libraries"
      value        = "pgaudit,pg_stat_statements"
      apply_method = "pending-reboot"
    },
    {
      name         = "rds.logical_replication"
      value        = var.enable_logical_replication ? "1" : "0"
      apply_method = "pending-reboot"
    },
    {
      name         = "password_encryption"
      value        = "scram-sha-256"
      apply_method = "immediate"
    },
    {
      name         = "pgaudit.log"
      value        = var.pgaudit_log
      apply_method = "immediate"
    },
    {
      name         = "pgaudit.log_parameter"
      value        = "0"
      apply_method = "immediate"
    },
    {
      name         = "pgaudit.log_catalog"
      value        = "0"
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
      value        = tostring(var.slow_query_threshold_ms)
      apply_method = "immediate"
    },
    {
      name         = "statement_timeout"
      value        = tostring(var.statement_timeout_ms)
      apply_method = "immediate"
    },
    {
      name         = "idle_in_transaction_session_timeout"
      value        = tostring(var.idle_in_transaction_session_timeout_ms)
      apply_method = "immediate"
    },
    {
      name         = "lock_timeout"
      value        = tostring(var.lock_timeout_ms)
      apply_method = "immediate"
    },
    {
      name         = "pg_stat_statements.track"
      value        = "all"
      apply_method = "immediate"
    },
    {
      name         = "rds.log_retention_period"
      value        = "4320"
      apply_method = "immediate"
    },
  ]

  db_parameters = [
    {
      name         = "random_page_cost"
      value        = "1.1"
      apply_method = "immediate"
    },
  ]
}

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.name_prefix}-cluster-"
  family      = data.aws_rds_engine_version.primary.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-cluster-"
  family      = data.aws_rds_engine_version.primary.parameter_group_family
  description = "Production Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  name_prefix = "${local.name_prefix}-db-"
  family      = data.aws_rds_engine_version.primary.parameter_group_family
  description = "Production Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.primary_region})"

  dynamic "parameter" {
    for_each = local.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name_prefix}-db-"
  family      = data.aws_rds_engine_version.primary.parameter_group_family
  description = "Production Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.secondary_region})"

  dynamic "parameter" {
    for_each = local.db_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
