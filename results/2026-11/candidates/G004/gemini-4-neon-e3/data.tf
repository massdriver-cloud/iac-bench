data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# ------------------------------------------------------------------------------
# Primary region discovery: VPC apps-<environment> & database subnets (tier=database)
# ------------------------------------------------------------------------------

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
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

data "aws_subnet" "primary_database" {
  for_each = toset(data.aws_subnets.primary_database.ids)
  id       = each.value
}

data "aws_rds_engine_version" "primary" {
  engine      = "aurora-postgresql"
  version     = var.engine_version
  include_all = true
}

# ------------------------------------------------------------------------------
# Secondary region discovery: VPC apps-<environment> & database subnets (tier=database)
# ------------------------------------------------------------------------------

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
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

data "aws_subnet" "secondary_database" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary_database.ids)
  id       = each.value
}

data "aws_rds_engine_version" "secondary" {
  provider    = aws.secondary
  engine      = "aurora-postgresql"
  version     = var.engine_version
  include_all = true
}
