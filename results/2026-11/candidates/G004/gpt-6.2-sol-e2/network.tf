locals {
  prefix        = "${var.environment}-${var.name}"
  primary_id    = "${local.prefix}-primary"
  secondary_id  = "${local.prefix}-secondary"
  vpc_name      = "apps-${var.environment}"
  database_name = replace(var.name, "-", "_")
  app_db_user   = "app_${local.database_name}"
  admin_user    = "dbadmin"
  port          = 5432
  tags = {
    Environment = var.environment
    Service     = var.name
    ManagedBy   = "OpenTofu"
  }
}

data "aws_vpc" "primary" {
  tags = { Name = local.vpc_name }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = local.vpc_name }
}

# A zonal query lets instance placement and validation use the same inventory.
data "aws_availability_zones" "primary" {
  state = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_availability_zones" "secondary" {
  provider = aws.secondary
  state    = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

data "aws_subnets" "primary_zonal" {
  for_each = toset(data.aws_availability_zones.primary.names)
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "availability-zone"
    values = [each.key]
  }
  tags = { tier = "database" }
}

data "aws_subnets" "secondary_zonal" {
  provider = aws.secondary
  for_each = toset(data.aws_availability_zones.secondary.names)
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  filter {
    name   = "availability-zone"
    values = [each.key]
  }
  tags = { tier = "database" }
}

locals {
  primary_azs          = sort([for az, subnets in data.aws_subnets.primary_zonal : az if length(subnets.ids) > 0])
  secondary_azs        = sort([for az, subnets in data.aws_subnets.secondary_zonal : az if length(subnets.ids) > 0])
  primary_subnet_ids   = flatten([for subnets in values(data.aws_subnets.primary_zonal) : subnets.ids])
  secondary_subnet_ids = flatten([for subnets in values(data.aws_subnets.secondary_zonal) : subnets.ids])
}

resource "aws_db_subnet_group" "primary" {
  name       = local.primary_id
  subnet_ids = local.primary_subnet_ids
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "The primary apps VPC needs tier=database private subnets in at least two AZs."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = local.secondary_id
  subnet_ids = local.secondary_subnet_ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "The secondary apps VPC needs tier=database private subnets in at least two AZs."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = local.primary_id
  description = "Private Aurora PostgreSQL in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = local.secondary_id
  description = "Private Aurora PostgreSQL in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary_eks" {
  for_each                     = var.eks_source_security_group_ids.primary
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.key
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_ingress_rule" "secondary_eks" {
  provider                     = aws.secondary
  for_each                     = var.eks_source_security_group_ids.secondary
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.key
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_ingress_rule" "primary_routed" {
  for_each          = var.additional_client_ipv4_cidrs.primary
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
}

resource "aws_vpc_security_group_ingress_rule" "secondary_routed" {
  provider          = aws.secondary
  for_each          = var.additional_client_ipv4_cidrs.secondary
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.key
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
}
