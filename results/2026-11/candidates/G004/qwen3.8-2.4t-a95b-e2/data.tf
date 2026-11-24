data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# The network team owns one VPC per environment per region (apps-staging and
# apps-prod). This module discovers that network; it never creates it.
data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

# Private database subnets the network team has already provisioned in each
# region, tagged tier = database.
data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}
