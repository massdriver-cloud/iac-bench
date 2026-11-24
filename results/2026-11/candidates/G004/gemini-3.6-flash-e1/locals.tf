locals {
  name_prefix = "${var.service_name}-${var.environment}"

  database_name = var.database_name != null && var.database_name != "" ? var.database_name : replace(var.service_name, "-", "_")

  target_vpc_name = var.vpc_name != "" ? var.vpc_name : (startswith(var.environment, "apps-") ? var.environment : "apps-${var.environment}")

  postgres_major_version = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.postgres_major_version}"

  common_tags = merge(
    {
      Service     = var.service_name
      Environment = var.environment
      ManagedBy   = "OpenTofu"
      Module      = "aurora-postgres-global"
    },
    var.tags
  )
}
