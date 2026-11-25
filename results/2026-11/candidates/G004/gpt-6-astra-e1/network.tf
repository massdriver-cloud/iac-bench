locals {
  prefix = "${var.name}-${var.environment}"
  tags = merge(var.tags, {
    Service   = var.name, Environment = var.environment,
    ManagedBy = "OpenTofu", DataClassification = "customer-payment"
  })
  primary_azs   = sort(distinct([for subnet in data.aws_subnet.primary : subnet.availability_zone]))
  secondary_azs = sort(distinct([for subnet in data.aws_subnet.secondary : subnet.availability_zone]))
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
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
  name       = "${local.prefix}-primary"
  subnet_ids = data.aws_subnets.primary.ids
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2 && alltrue([for s in data.aws_subnet.primary : !s.map_public_ip_on_launch])
      error_message = "Primary database subnets must span at least two AZs and must not assign public IPs. Network owners must also ensure private route tables."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.prefix}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2 && alltrue([for s in data.aws_subnet.secondary : !s.map_public_ip_on_launch])
      error_message = "Secondary database subnets must span at least two AZs and must not assign public IPs."
    }
  }
}

resource "aws_security_group" "primary" {
  name_prefix = "${local.prefix}-db-"
  description = "Private PostgreSQL; only approved EKS security groups"
  vpc_id      = data.aws_vpc.primary.id
  # No outbound rules: established response traffic is stateful; Aurora replication is service-managed.
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.prefix}-db-"
  description = "Private PostgreSQL DR; only approved EKS security groups"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Approved EKS workload PostgreSQL access"
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "Approved EKS workload PostgreSQL access"
}
