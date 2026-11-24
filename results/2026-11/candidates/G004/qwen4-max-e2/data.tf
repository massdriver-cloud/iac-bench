###############################################################################
# The network team owns the VPCs and subnets. We discover, never create:
#   VPC:     Name tag = "apps-<environment>" in each region
#   Subnets: tier = database within that VPC
###############################################################################

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

data "aws_vpc" "primary" {
  provider = aws.primary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "database_primary" {
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

data "aws_subnets" "database_secondary" {
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
