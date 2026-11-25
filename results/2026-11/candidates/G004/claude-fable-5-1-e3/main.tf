locals {
  name          = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  vpc_name      = "apps-${var.environment}"

  engine                 = "aurora-postgresql"
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "${local.engine}${local.engine_major_version}"

  tags = merge(var.tags, {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "opentofu"
    Module      = "aurora-postgresql-global"
  })

  # Baseline cluster parameters applied in both regions.
  # - rds.force_ssl           : refuse unencrypted connections (payment data in flight)
  # - rds.global_db_rpo       : enforce the business RPO at the engine level
  # - pgaudit / log_*         : audit trail for who connected and what changed
  # - shared_preload_libraries: static parameter, needs a reboot to take effect
  baseline_cluster_parameters = [
    { name = "rds.force_ssl", value = "1", apply_method = "immediate" },
    { name = "rds.global_db_rpo", value = tostring(var.rpo_seconds), apply_method = "immediate" },
    { name = "shared_preload_libraries", value = "pg_stat_statements,pgaudit", apply_method = "pending-reboot" },
    { name = "pgaudit.log", value = "ddl,role", apply_method = "immediate" },
    { name = "log_connections", value = "1", apply_method = "immediate" },
    { name = "log_disconnections", value = "1", apply_method = "immediate" },
    { name = "log_min_duration_statement", value = "1000", apply_method = "immediate" },
    { name = "log_statement", value = "ddl", apply_method = "immediate" },
  ]

  cluster_parameters = concat(local.baseline_cluster_parameters, var.additional_cluster_parameters)
}

data "aws_partition" "current" {}

data "aws_caller_identity" "current" {}

############################################
# Network discovery: the network team's VPCs and database subnets
############################################

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
