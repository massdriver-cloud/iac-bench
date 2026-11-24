data "aws_caller_identity" "primary" {
  provider = aws
}

data "aws_caller_identity" "secondary" {
  provider = aws.secondary
}

data "aws_vpc" "primary" {
  provider = aws
  filter {
    name   = "tag:Name"
    values = [local.target_vpc_name]
  }
}

data "aws_subnets" "primary" {
  provider = aws
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = [local.target_vpc_name]
  }
}

data "aws_subnets" "secondary" {
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
