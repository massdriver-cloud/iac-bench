locals {
  name = "${var.service_name}-${var.environment}"
  tags = { Service = var.service_name, Environment = var.environment, ManagedBy = "OpenTofu" }
}
data "aws_vpc" "primary" {
  tags = { Name = "apps-${var.environment}" }
}
data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = "apps-${var.environment}" }
}
data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
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
data "aws_subnet" "primary" {
  for_each = toset(data.aws_subnets.primary.ids)
  id       = each.value
}
data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.value
}
resource "aws_db_subnet_group" "primary" {
  name       = "${local.name}-primary"
  subnet_ids = data.aws_subnets.primary.ids
  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary : s.availability_zone])) >= 2
      error_message = "The primary VPC must have database-tagged subnets in at least two AZs."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.name}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary : s.availability_zone])) >= 2
      error_message = "The secondary VPC must have database-tagged subnets in at least two AZs."
    }
  }
}
resource "aws_security_group" "primary" {
  name        = "${local.name}-aurora-primary"
  description = "PostgreSQL from approved EKS security groups"
  vpc_id      = data.aws_vpc.primary.id
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-aurora-secondary"
  description = "PostgreSQL from approved EKS security groups"
  vpc_id      = data.aws_vpc.secondary.id
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
