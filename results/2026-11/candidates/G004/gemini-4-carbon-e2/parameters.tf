resource "aws_rds_cluster_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.name_prefix}-cluster-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${var.service_name} (${var.environment}) in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster-${var.primary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.name_prefix}-cluster-"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${var.service_name} (${var.environment}) in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.effective_cluster_parameters
    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-cluster-${var.secondary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  region      = var.primary_region
  name_prefix = "${local.name_prefix}-instance-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL instance parameter group for ${var.service_name} (${var.environment}) in ${var.primary_region}"

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = tostring(var.slow_query_log_threshold_ms)
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = tostring(var.idle_in_transaction_timeout_ms)
    apply_method = "immediate"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-instance-${var.primary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  region      = var.secondary_region
  name_prefix = "${local.name_prefix}-instance-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL instance parameter group for ${var.service_name} (${var.environment}) in ${var.secondary_region}"

  parameter {
    name         = "log_connections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_disconnections"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "log_min_duration_statement"
    value        = tostring(var.slow_query_log_threshold_ms)
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = tostring(var.idle_in_transaction_timeout_ms)
    apply_method = "immediate"
  }

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-instance-${var.secondary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}
