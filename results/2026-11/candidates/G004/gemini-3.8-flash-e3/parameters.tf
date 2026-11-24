resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${var.name}-primary-cpg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${var.name} (primary region)"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary-cpg"
      Region = var.primary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${var.name}-secondary-cpg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${var.name} (secondary region)"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  parameter {
    name  = "log_lock_waits"
    value = "1"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name         = "shared_preload_libraries"
    value        = "pg_stat_statements"
    apply_method = "pending-reboot"
  }

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary-cpg"
      Region = var.secondary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "primary" {
  name_prefix = "${var.name}-primary-pg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL DB parameter group for ${var.name} (primary region)"

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary-pg"
      Region = var.primary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${var.name}-secondary-pg-"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL DB parameter group for ${var.name} (secondary region)"

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary-pg"
      Region = var.secondary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}
