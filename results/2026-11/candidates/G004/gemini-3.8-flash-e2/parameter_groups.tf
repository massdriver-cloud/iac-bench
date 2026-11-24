# Cluster and Instance Parameter Groups for hardened PostgreSQL configuration

resource "aws_rds_cluster_parameter_group" "primary" {
  name        = "${local.name_prefix}-primary-cluster-pg"
  family      = local.parameter_group_family
  description = "Production hardened cluster parameter group for ${var.service_name} primary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-cluster-pg"
  family      = local.parameter_group_family
  description = "Production hardened cluster parameter group for ${var.service_name} secondary cluster"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  parameter {
    name  = "log_statement"
    value = "ddl"
  }

  parameter {
    name  = "log_min_duration_statement"
    value = "1000"
  }

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }
}

resource "aws_db_parameter_group" "primary" {
  name        = "${local.name_prefix}-primary-instance-pg"
  family      = local.parameter_group_family
  description = "Production hardened DB instance parameter group for ${var.service_name} primary instances"
}

resource "aws_db_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-instance-pg"
  family      = local.parameter_group_family
  description = "Production hardened DB instance parameter group for ${var.service_name} secondary instances"
}
