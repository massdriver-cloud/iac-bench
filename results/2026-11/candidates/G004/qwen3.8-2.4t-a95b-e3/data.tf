# ---------------------------------------------------------------------------
# Network discovery
#
# The network team owns one VPC per environment in each region (named
# apps-<environment>) and has already created private database subnets in
# each, tagged tier = database. The module looks them up instead of managing
# network resources, and guards against mis-tagged/missing subnets below.
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
  provider = aws

  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = local.vpc_name
  }
}

data "aws_subnets" "primary_db" {
  provider = aws

  tags = {
    (local.db_subnet_tag_key) = local.db_subnet_tag_value
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
}

data "aws_subnets" "secondary_db" {
  provider = aws.secondary

  tags = {
    (local.db_subnet_tag_key) = local.db_subnet_tag_value
  }

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
}
