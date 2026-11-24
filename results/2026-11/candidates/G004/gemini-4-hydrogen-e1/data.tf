data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

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

data "aws_subnets" "primary_db" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
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

data "aws_rds_engine_version" "primary" {
  engine  = "aurora-postgresql"
  version = var.engine_major_version
  latest  = true
}
