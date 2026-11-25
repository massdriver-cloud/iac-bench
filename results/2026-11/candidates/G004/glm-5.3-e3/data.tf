###############################################################################
# Network discovery.
#
# The network team owns one apps VPC per environment in every region our
# services run in, and has already created the private database subnets inside
# each. The module finds that existing infrastructure instead of creating it:
# the VPC by its Name tag (apps-staging / apps-prod), and its database
# subnets by the tier=database tag. Explicit VPC IDs can be passed to target a
# VPC that doesn't follow the convention.
###############################################################################

data "aws_partition" "current" {
  provider = aws.primary
}

data "aws_vpc" "primary_by_name" {
  provider = aws.primary
  count    = var.primary_vpc_id == null ? 1 : 0

  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpc" "primary_by_id" {
  provider = aws.primary
  count    = var.primary_vpc_id != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }
}

data "aws_subnets" "primary" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [local.primary_vpc.id]
  }

  # Private database subnets, created and owned by the network team.
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_vpc" "secondary_by_name" {
  provider = aws.secondary
  count    = var.secondary_vpc_id == null ? 1 : 0

  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpc" "secondary_by_id" {
  provider = aws.secondary
  count    = var.secondary_vpc_id != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [local.secondary_vpc.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
