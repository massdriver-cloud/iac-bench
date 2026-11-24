locals {
  # Common prefix for every resource: <service>-<environment>, always lowercase.
  stack = lower("${var.name}-${var.environment}")

  engine        = "aurora-postgresql"
  engine_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  database_name = var.database_name != null ? var.database_name : replace(lower(var.name), "-", "_")

  # The network team owns one VPC per environment, named apps-<environment>,
  # with private database subnets tagged tier = database in each region.
  vpc_name            = var.vpc_name != null ? var.vpc_name : "apps-${var.environment}"
  db_subnet_tag_key   = "tier"
  db_subnet_tag_value = "database"

  allowed_sgs_primary     = var.allowed_security_group_ids.primary
  allowed_sgs_secondary   = var.allowed_security_group_ids.secondary
  allowed_cidrs_primary   = var.allowed_cidr_blocks.primary
  allowed_cidrs_secondary = var.allowed_cidr_blocks.secondary

  # These databases hold customer and payment data: clients must connect over
  # TLS. Platform teams can override (or extend) via var.cluster_parameters.
  cluster_parameters = merge({ "rds.force_ssl" = "1" }, var.cluster_parameters)

  tags = merge(
    {
      Service     = var.name
      Environment = var.environment
      Component   = "aurora-postgresql"
      ManagedBy   = "opentofu"
      DataClass   = "customer-payment"
    },
    var.tags,
  )
}
