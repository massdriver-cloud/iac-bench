locals {
  # Normalize environment name to match VPC tag 'apps-staging' or 'apps-prod'
  vpc_name = startswith(var.environment, "apps-") ? var.environment : "apps-${var.environment}"
  env_name = replace(local.vpc_name, "apps-", "")

  # Database name sanitized for PostgreSQL identifier requirements
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))

  # Common naming prefixes
  name_prefix = "${var.service_name}-${local.env_name}"

  # Resolved engine version & parameter group family
  engine_version         = data.aws_rds_engine_version.postgresql.version
  parameter_group_family = data.aws_rds_engine_version.postgresql.parameter_group_family

  default_tags = merge(
    {
      "Service"     = var.service_name
      "Environment" = local.env_name
      "ManagedBy"   = "OpenTofu"
      "Tier"        = "database"
      "DataClass"   = "customer-payment"
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}

data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}
