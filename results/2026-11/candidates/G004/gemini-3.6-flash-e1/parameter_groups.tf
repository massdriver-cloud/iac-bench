resource "aws_rds_cluster_parameter_group" "primary" {
  provider    = aws
  name        = "${local.name_prefix}-primary-cluster-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${local.name_prefix} primary"

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

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-cluster-pg"
  family      = local.parameter_group_family
  description = "Aurora PostgreSQL cluster parameter group for ${local.name_prefix} secondary"

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

  tags = local.common_tags

  lifecycle {
    create_before_destroy = true
  }
}
