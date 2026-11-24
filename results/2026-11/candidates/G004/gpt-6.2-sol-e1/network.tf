provider "aws" {
  region = var.regions.primary
}

provider "aws" {
  alias  = "secondary"
  region = var.regions.secondary
}

locals {
  name     = "${var.name}-${var.environment}"
  vpc_name = "apps-${var.environment}"
  port     = 5432
  admin    = "platform_admin"
  tags = merge(var.tags, {
    Service     = var.name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  })
  primary_azs      = sort(distinct([for subnet in data.aws_subnet.primary : subnet.availability_zone]))
  secondary_azs    = sort(distinct([for subnet in data.aws_subnet.secondary : subnet.availability_zone]))
  primary_db_azs   = slice(local.primary_azs, 0, min(3, length(local.primary_azs)))
  secondary_db_azs = slice(local.secondary_azs, 0, min(3, length(local.secondary_azs)))
}

data "aws_vpc" "primary" {
  tags = { Name = local.vpc_name }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = local.vpc_name }
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
  id       = each.key
}

data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.key
}

resource "aws_db_subnet_group" "primary" {
  name       = local.name
  subnet_ids = [for subnet in data.aws_subnet.primary : subnet.id if contains(local.primary_db_azs, subnet.availability_zone)]
  tags       = local.tags

  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "The primary apps VPC needs database-tagged subnets in at least two AZs."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = local.name
  subnet_ids = [for subnet in data.aws_subnet.secondary : subnet.id if contains(local.secondary_db_azs, subnet.availability_zone)]
  tags       = local.tags

  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "The secondary apps VPC needs database-tagged subnets in at least two AZs."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-db"
  description = "Private Aurora listeners for ${local.name}"
  vpc_id      = data.aws_vpc.primary.id
  tags        = local.tags
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-db"
  description = "Private Aurora listeners for ${local.name}"
  vpc_id      = data.aws_vpc.secondary.id
  tags        = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.eks_client_security_groups.primary
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.key
  description                  = "Local EKS database clients"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  tags                         = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.eks_client_security_groups.secondary
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.key
  description                  = "Local EKS database clients"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  tags                         = local.tags
}
