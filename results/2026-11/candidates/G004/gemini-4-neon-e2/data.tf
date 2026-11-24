data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

################################################################################
# Network Discovery (Owned by Network Team: VPC apps-<env>, subnets tier=database)
################################################################################

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_db" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnet" "primary_db" {
  provider = aws.primary
  for_each = toset(data.aws_subnets.primary_db.ids)
  id       = each.value
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary_db" {
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

data "aws_subnet" "secondary_db" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary_db.ids)
  id       = each.value
}

################################################################################
# Aurora PostgreSQL Engine Validation Across Both Regions
################################################################################

data "aws_rds_engine_version" "primary" {
  provider = aws.primary
  engine   = "aurora-postgresql"
  version  = var.engine_version
}

data "aws_rds_engine_version" "secondary" {
  provider = aws.secondary
  engine   = "aurora-postgresql"
  version  = var.engine_version
}

################################################################################
# Cross-Variable & Environment Invariant Checks
################################################################################

check "distinct_regions" {
  assert {
    condition     = var.primary_region != var.secondary_region
    error_message = "primary_region (${var.primary_region}) and secondary_region (${var.secondary_region}) must be different US AWS regions for regional disaster recovery."
  }
}

check "global_database_engine_support" {
  assert {
    condition     = data.aws_rds_engine_version.primary.supports_global_databases && data.aws_rds_engine_version.secondary.supports_global_databases
    error_message = "Aurora PostgreSQL version ${var.engine_version} must support Aurora Global Databases in both ${var.primary_region} and ${var.secondary_region}."
  }
}

check "serverlessv2_capacity_bounds" {
  assert {
    condition     = var.serverlessv2_max_capacity >= var.serverlessv2_min_capacity
    error_message = "serverlessv2_max_capacity (${var.serverlessv2_max_capacity}) must be >= serverlessv2_min_capacity (${var.serverlessv2_min_capacity})."
  }
}
