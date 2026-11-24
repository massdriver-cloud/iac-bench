data "aws_caller_identity" "current" {}

data "aws_rds_engine_version" "primary" {
  engine  = "aurora-postgresql"
  version = var.engine_version
}

data "aws_rds_engine_version" "secondary" {
  provider = aws.secondary
  engine   = "aurora-postgresql"
  version  = var.engine_version
}

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }

  filter {
    name   = "tag:environment"
    values = [var.environment]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }

  filter {
    name   = "tag:environment"
    values = [var.environment]
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

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "At least two private subnets tagged tier=database are required in primary VPC ${local.vpc_name}."
    }
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

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "At least two private subnets tagged tier=database are required in secondary VPC ${local.vpc_name}."
    }
  }
}
