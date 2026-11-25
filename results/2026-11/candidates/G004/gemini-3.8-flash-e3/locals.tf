locals {
  # Normalize environment name to match VPC tag Name="apps-<env>"
  vpc_name = startswith(var.environment, "apps-") ? var.environment : "apps-${var.environment}"
  env_name = replace(var.environment, "^apps-", "")

  # Sanitized database name for PostgreSQL (no dashes allowed)
  database_name = coalesce(var.database_name, replace(var.name, "-", "_"))

  # Account ID
  account_id = data.aws_caller_identity.current.account_id

  # Engine version and family
  engine_version         = coalesce(var.engine_version, data.aws_rds_engine_version.postgresql.version)
  parameter_group_family = data.aws_rds_engine_version.postgresql.parameter_group_family

  # Resolved VPC IDs
  primary_vpc_id   = coalesce(var.primary_vpc_id, try(data.aws_vpc.primary[0].id, null))
  secondary_vpc_id = coalesce(var.secondary_vpc_id, try(data.aws_vpc.secondary[0].id, null))

  # Resolved Subnet IDs
  primary_subnet_ids   = coalesce(var.primary_subnet_ids, try(data.aws_subnets.primary_db[0].ids, []))
  secondary_subnet_ids = coalesce(var.secondary_subnet_ids, try(data.aws_subnets.secondary_db[0].ids, []))

  # Resolved VPC CIDR blocks for security group ingress
  primary_vpc_cidr   = try(data.aws_vpc.primary[0].cidr_block, null)
  secondary_vpc_cidr = try(data.aws_vpc.secondary[0].cidr_block, null)

  # KMS Key ARNs
  primary_kms_key_arn   = coalesce(var.primary_kms_key_arn, try(aws_kms_key.primary[0].arn, null))
  secondary_kms_key_arn = coalesce(var.secondary_kms_key_arn, try(aws_kms_key.secondary[0].arn, null))

  # Common tags
  common_tags = merge(
    {
      "Service"     = var.name
      "Environment" = local.env_name
      "ManagedBy"   = "OpenTofu"
      "Tier"        = "database"
      "Compliance"  = "PCI-DSS"
    },
    var.tags
  )
}
