resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name_prefix}-aurora-pg-cluster-primary"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.primary_region})."

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "pgaudit.log"
    value        = var.pgaudit_log
    apply_method = "immediate"
  }

  parameter {
    name         = "password_encryption"
    value        = "scram-sha-256"
    apply_method = "immediate"
  }

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
    name         = "log_min_duration_statement"
    value        = tostring(var.slow_query_threshold_ms)
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = tostring(var.idle_in_transaction_session_timeout_ms)
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-aurora-pg-cluster-primary"
    Role = "primary"
  }
}

resource "aws_db_parameter_group" "primary" {
  name        = "${local.name_prefix}-aurora-pg-instance-primary"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.primary_region})."

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "deadlock_timeout"
    value        = "1000"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-aurora-pg-instance-primary"
    Role = "primary"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-aurora-pg-cluster-secondary"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL cluster parameter group for ${local.name_prefix} (${var.secondary_region})."

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements,pgaudit"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "pgaudit.log"
    value        = var.pgaudit_log
    apply_method = "immediate"
  }

  parameter {
    name         = "password_encryption"
    value        = "scram-sha-256"
    apply_method = "immediate"
  }

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
    name         = "log_min_duration_statement"
    value        = tostring(var.slow_query_threshold_ms)
    apply_method = "immediate"
  }

  parameter {
    name         = "idle_in_transaction_session_timeout"
    value        = tostring(var.idle_in_transaction_session_timeout_ms)
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-aurora-pg-cluster-secondary"
    Role = "secondary"
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-aurora-pg-instance-secondary"
  family      = local.parameter_group_family
  description = "Hardened Aurora PostgreSQL instance parameter group for ${local.name_prefix} (${var.secondary_region})."

  parameter {
    name         = "log_lock_waits"
    value        = "1"
    apply_method = "immediate"
  }

  parameter {
    name         = "deadlock_timeout"
    value        = "1000"
    apply_method = "immediate"
  }

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.name_prefix}-aurora-pg-instance-secondary"
    Role = "secondary"
  }
}
