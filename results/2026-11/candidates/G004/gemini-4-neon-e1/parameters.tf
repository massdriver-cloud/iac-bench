locals {
  # Database-specialist production PostgreSQL cluster parameters (security, auditing, reliability)
  # Defined as a map keyed by parameter name so service-specific overrides merge cleanly without duplicates.
  default_cluster_parameters = {
    "rds.force_ssl" = {
      value        = "1"
      apply_method = "pending-reboot"
    }
    "ssl_min_protocol_version" = {
      value        = "TLSv1.2"
      apply_method = "immediate"
    }
    "shared_preload_libraries" = {
      value        = "pg_stat_statements,pgaudit"
      apply_method = "pending-reboot"
    }
    "pgaudit.log" = {
      value        = var.pgaudit_log
      apply_method = "immediate"
    }
    "pgaudit.log_parameter" = {
      value        = "0"
      apply_method = "immediate"
    }
    "pg_stat_statements.track" = {
      value        = "all"
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
      value        = tostring(var.slow_query_log_threshold_ms)
      apply_method = "immediate"
    }
    "log_temp_files" = {
      value        = "0"
      apply_method = "immediate"
    }
    "deadlock_timeout" = {
      value        = "1000"
      apply_method = "immediate"
    }
    "idle_in_transaction_session_timeout" = {
      value        = tostring(var.idle_in_transaction_session_timeout_ms)
      apply_method = "immediate"
    }
    "statement_timeout" = {
      value        = tostring(var.statement_timeout_ms)
      apply_method = "immediate"
    }
  }

  cluster_parameters = merge(
    local.default_cluster_parameters,
    {
      for p in var.additional_cluster_parameters : p.name => {
        value        = p.value
        apply_method = p.apply_method
      }
    }
  )

  default_instance_parameters = {
    "log_min_duration_statement" = {
      value        = tostring(var.slow_query_log_threshold_ms)
      apply_method = "immediate"
    }
    "log_lock_waits" = {
      value        = "1"
      apply_method = "immediate"
    }
    "log_temp_files" = {
      value        = "0"
      apply_method = "immediate"
    }
    "idle_in_transaction_session_timeout" = {
      value        = tostring(var.idle_in_transaction_session_timeout_ms)
      apply_method = "immediate"
    }
    "statement_timeout" = {
      value        = tostring(var.statement_timeout_ms)
      apply_method = "immediate"
    }
  }

  instance_parameters = merge(
    local.default_instance_parameters,
    {
      for p in var.additional_instance_parameters : p.name => {
        value        = p.value
        apply_method = p.apply_method
      }
    }
  )
}

################################################################################
# Primary Region Parameter Groups
################################################################################

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.primary_cluster_id}-pg${local.engine_major_version}-"
  family      = local.parameter_group_family
  description = "Hardened production Aurora PostgreSQL cluster parameters for ${local.primary_cluster_id}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.primary_cluster_id}-cluster-pg"
    Role = "primary"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  name_prefix = "${local.primary_cluster_id}-db-pg${local.engine_major_version}-"
  family      = local.parameter_group_family
  description = "Hardened production Aurora PostgreSQL instance parameters for ${local.primary_cluster_id}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.primary_cluster_id}-instance-pg"
    Role = "primary"
  }

  lifecycle {
    create_before_destroy = true
  }
}

################################################################################
# Secondary Region Parameter Groups (Exact Parity for Seamless Failover)
################################################################################

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.secondary_cluster_id}-pg${local.engine_major_version}-"
  family      = local.parameter_group_family
  description = "Hardened production Aurora PostgreSQL cluster parameters for ${local.secondary_cluster_id}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.secondary_cluster_id}-cluster-pg"
    Role = "secondary"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.secondary_cluster_id}-db-pg${local.engine_major_version}-"
  family      = local.parameter_group_family
  description = "Hardened production Aurora PostgreSQL instance parameters for ${local.secondary_cluster_id}"

  dynamic "parameter" {
    for_each = local.instance_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${local.secondary_cluster_id}-instance-pg"
    Role = "secondary"
  }

  lifecycle {
    create_before_destroy = true
  }
}
