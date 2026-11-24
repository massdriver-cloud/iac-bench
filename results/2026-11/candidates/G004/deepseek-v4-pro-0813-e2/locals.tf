locals {
  service_name = lower(var.service_name)
  environment  = lower(var.environment)

  prefix = "${local.service_name}-${local.environment}"

  global_cluster_identifier    = "${local.prefix}-global"
  primary_cluster_identifier   = "${local.prefix}-primary"
  secondary_cluster_identifier = "${local.prefix}-secondary"

  engine_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  primary_subnet_ids   = flatten(data.aws_subnets.primary[*].ids)
  secondary_subnet_ids = flatten(data.aws_subnets.secondary[*].ids)

  default_tags = merge(
    var.tags,
    {
      Environment = var.environment
      Service     = var.service_name
      ManagedBy   = "opentofu"
      Tier        = "database"
    }
  )
}