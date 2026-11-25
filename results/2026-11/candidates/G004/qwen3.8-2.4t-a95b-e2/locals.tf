locals {
  # Every identifier hangs off this prefix so everything belonging to one
  # service + environment is trivially discoverable in both regions.
  prefix = lower("${var.service_name}-${var.environment}")

  global_cluster_identifier    = "${local.prefix}-global"
  primary_cluster_identifier   = local.prefix
  secondary_cluster_identifier = "${local.prefix}-dr"

  vpc_name      = coalesce(var.vpc_name, "apps-${var.environment}")
  database_name = coalesce(var.database_name, replace(lower(var.service_name), "-", "_"))

  engine                 = "aurora-postgresql"
  engine_port            = 5432
  parameter_group_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      ManagedBy          = "opentofu"
      DataClassification = "confidential" # customer + payment data
    },
    var.extra_tags,
  )
}
