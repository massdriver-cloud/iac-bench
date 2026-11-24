locals {
  name          = "${var.service}-${var.environment}-pg"
  vpc_name      = coalesce(var.vpc_name, "apps-${var.environment}")
  database_name = coalesce(var.database_name, replace(var.service, "-", "_"))
  pg_family     = "aurora-postgresql${element(split(".", var.engine_version), 0)}"
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Network discovery. The network team owns one VPC per environment per region
# (Name tag = apps-<environment>) with private database subnets tagged
# tier = database. We never create or modify network resources.
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
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

data "aws_subnets" "database_primary" {
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
