data "aws_caller_identity" "current" {}

data "aws_rds_engine_version" "postgresql" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}

data "aws_vpc" "primary" {
  count = var.primary_vpc_id == null ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  count    = var.secondary_vpc_id == null ? 1 : 0

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_db" {
  count = var.primary_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.primary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary_db" {
  provider = aws.secondary
  count    = var.secondary_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.secondary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
