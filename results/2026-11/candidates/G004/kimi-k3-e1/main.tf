locals {
  engine_major_version   = split(".", var.engine_version)[0]
  parameter_group_family = "aurora-postgresql${local.engine_major_version}"

  # TLS is non-negotiable for clusters holding customer and payment data, so
  # rds.force_ssl is always present; callers can still add or override
  # parameters via var.cluster_parameters.
  cluster_parameters = merge(
    { "rds.force_ssl" = "1" },
    var.cluster_parameters,
  )

  primary_cluster_identifier   = "${var.name}-primary"
  secondary_cluster_identifier = "${var.name}-secondary"
}

# Regional foundations (network discovery, DB subnet group, security group,
# KMS key, cluster parameter group) are identical in both regions apart from
# the provider, so they live in a small local submodule.
module "primary_region" {
  source = "./modules/regional"

  name                       = var.name
  vpc_tags                   = var.vpc_tags
  subnet_tags                = var.subnet_tags
  allowed_cidr_blocks        = var.allowed_cidr_blocks
  allowed_security_group_ids = var.allowed_security_group_ids
  cluster_parameters         = local.cluster_parameters
  parameter_group_family     = local.parameter_group_family
  port                       = var.port
}

module "secondary_region" {
  source = "./modules/regional"

  providers = {
    aws = aws.secondary
  }

  name                       = var.name
  vpc_tags                   = var.vpc_tags
  subnet_tags                = var.subnet_tags
  allowed_cidr_blocks        = var.allowed_cidr_blocks
  allowed_security_group_ids = var.allowed_security_group_ids
  cluster_parameters         = local.cluster_parameters
  parameter_group_family     = local.parameter_group_family
  port                       = var.port
}
