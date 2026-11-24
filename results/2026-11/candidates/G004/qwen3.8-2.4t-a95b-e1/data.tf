# ---------------------------------------------------------------------------
# Account / partition facts
# ---------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

data "aws_region" "primary" {}
data "aws_region" "secondary" {
  provider = aws.dr
}

# ---------------------------------------------------------------------------
# Network discovery. The network team owns one VPC per environment
# ("apps-staging" / "apps-prod") in each region and has already created the
# private database subnets, tagged tier = database. The module finds them
# instead of making every caller look them up by hand.
# ---------------------------------------------------------------------------

data "aws_vpcs" "primary" {
  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpcs" "secondary" {
  provider = aws.dr

  tags = {
    Name = local.vpc_name
  }
}

locals {
  primary_vpc_id   = tolist(data.aws_vpcs.primary.ids)[0]
  secondary_vpc_id = tolist(data.aws_vpcs.secondary.ids)[0]
}

data "aws_vpc" "primary" {
  id = local.primary_vpc_id
}

data "aws_vpc" "secondary" {
  provider = aws.dr
  id       = local.secondary_vpc_id
}

data "aws_subnets" "database_primary" {
  tags = {
    tier = "database"
  }

  filter {
    name   = "vpc-id"
    values = [local.primary_vpc_id]
  }
}

data "aws_subnets" "database_secondary" {
  provider = aws.dr

  tags = {
    tier = "database"
  }

  filter {
    name   = "vpc-id"
    values = [local.secondary_vpc_id]
  }
}
