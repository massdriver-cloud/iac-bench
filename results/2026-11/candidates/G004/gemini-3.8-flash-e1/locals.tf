locals {
  database_name = var.database_name != null ? var.database_name : replace(var.name, "-", "_")

  parameter_group_family = var.parameter_group_family != null ? var.parameter_group_family : "aurora-postgresql${split(".", var.engine_version)[0]}"

  secondary_instance_class = var.secondary_instance_class != null ? var.secondary_instance_class : var.instance_class

  primary_vpc_id         = data.aws_vpc.primary.id
  primary_vpc_cidr_block = data.aws_vpc.primary.cidr_block
  primary_subnet_ids     = var.primary_database_subnet_ids != null ? var.primary_database_subnet_ids : data.aws_subnets.primary.ids

  secondary_vpc_id         = data.aws_vpc.secondary.id
  secondary_vpc_cidr_block = data.aws_vpc.secondary.cidr_block
  secondary_subnet_ids     = var.secondary_database_subnet_ids != null ? var.secondary_database_subnet_ids : data.aws_subnets.secondary.ids

  primary_allowed_cidrs   = var.allowed_cidr_blocks != null ? var.allowed_cidr_blocks : [local.primary_vpc_cidr_block]
  secondary_allowed_cidrs = var.secondary_allowed_cidr_blocks != null ? var.secondary_allowed_cidr_blocks : (var.allowed_cidr_blocks != null ? var.allowed_cidr_blocks : [local.secondary_vpc_cidr_block])

  primary_kms_key_arn   = var.primary_kms_key_arn != null ? var.primary_kms_key_arn : aws_kms_key.primary[0].arn
  secondary_kms_key_arn = var.secondary_kms_key_arn != null ? var.secondary_kms_key_arn : aws_kms_key.secondary[0].arn

  common_tags = merge(
    {
      Environment = var.environment
      Service     = var.name
      ManagedBy   = "OpenTofu"
      Tier        = "database"
    },
    var.tags
  )

  primary_tags = merge(
    local.common_tags,
    {
      Region = var.primary_region
    }
  )

  secondary_tags = merge(
    local.common_tags,
    {
      Region = var.secondary_region
    }
  )
}
