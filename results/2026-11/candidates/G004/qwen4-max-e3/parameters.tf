# TLS is mandatory (customer/payment data in transit), and we log connections
# and DDL plus slow statements for audit and incident response.
# Parameter groups are regional resources, so one set per region.

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = local.name
  family      = local.pg_family
  description = "Cluster parameters for ${local.name} (primary)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = local.name
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  family      = local.pg_family
  description = "Cluster parameters for ${local.name} (DR)"

  parameter {
    name         = "rds.force_ssl"
    value        = "1"
    apply_method = "pending-reboot"
  }

  tags = {
    Name = local.name
  }
}

resource "aws_db_parameter_group" "primary" {
  provider = aws.primary

  name        = local.name
  family      = local.pg_family
  description = "Instance parameters for ${local.name} (primary)"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
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

  tags = {
    Name = local.name
  }
}

resource "aws_db_parameter_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  family      = local.pg_family
  description = "Instance parameters for ${local.name} (DR)"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
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

  tags = {
    Name = local.name
  }
}
