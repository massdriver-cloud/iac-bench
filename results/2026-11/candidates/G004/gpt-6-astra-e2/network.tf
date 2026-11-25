locals {
  name = "${var.name}-${var.environment}"
  tags = merge(var.tags, {
    Service     = var.name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
    DataClass   = "confidential"
  })
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
  tags = { tier = "database" }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = { tier = "database" }
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
      condition     = length(toset([for s in data.aws_subnet.primary : s.availability_zone])) >= 2
      error_message = "Primary database subnets must span at least two AZs."
    }
    precondition {
      condition     = alltrue([for s in data.aws_subnet.primary : !s.map_public_ip_on_launch])
      error_message = "Database subnets must not auto-assign public addresses."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.name}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(toset([for s in data.aws_subnet.secondary : s.availability_zone])) >= 2
      error_message = "Secondary database subnets must span at least two AZs."
    }
    precondition {
      condition     = alltrue([for s in data.aws_subnet.secondary : !s.map_public_ip_on_launch])
      error_message = "Database subnets must not auto-assign public addresses."
    }
  }
}

resource "aws_security_group" "primary" {
  name_prefix = "${local.name}-db-"
  description = "Private PostgreSQL from explicitly authorized EKS workloads only"
  vpc_id      = data.aws_vpc.primary.id
  # No initiated outbound traffic is required; SGs are stateful.
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.name}-db-"
  description = "Private PostgreSQL from explicitly authorized EKS workloads only"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.clients.primary.security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from authorized workload"
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.clients.secondary.security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from authorized workload"
}
