# Network discovery.
#
# The network team owns one VPC per environment in each region, tagged
# Name = "apps-<environment>", with private database subnets tagged
# "tier = database". The module discovers both by tag so consumers don't have
# to plumb IDs around. Explicit IDs can be injected via the *_vpc_id /
# *_database_subnet_ids overrides (escape hatch, not the standard path).

data "aws_vpc" "primary" {
  provider = aws.primary
  id       = var.primary_vpc_id

  dynamic "filter" {
    for_each = var.primary_vpc_id == null ? [local.vpc_name] : []
    content {
      name   = "tag:Name"
      values = [filter.value]
    }
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  id       = var.secondary_vpc_id

  dynamic "filter" {
    for_each = var.secondary_vpc_id == null ? [local.vpc_name] : []
    content {
      name   = "tag:Name"
      values = [filter.value]
    }
  }
}

data "aws_subnets" "primary" {
  provider = aws.primary
  count    = var.primary_database_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:${var.database_subnet_tag_key}"
    values = [var.database_subnet_tag_value]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  count    = var.secondary_database_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:${var.database_subnet_tag_key}"
    values = [var.database_subnet_tag_value]
  }
}

locals {
  primary_subnet_ids   = var.primary_database_subnet_ids != null ? var.primary_database_subnet_ids : data.aws_subnets.primary[0].ids
  secondary_subnet_ids = var.secondary_database_subnet_ids != null ? var.secondary_database_subnet_ids : data.aws_subnets.secondary[0].ids

  # EKS services reach the database from inside the VPC, so the VPC CIDR is
  # allowed by default; additional CIDRs / security groups layer on top.
  primary_allowed_cidrs   = toset(concat([data.aws_vpc.primary.cidr_block], var.additional_allowed_cidr_blocks))
  secondary_allowed_cidrs = toset(concat([data.aws_vpc.secondary.cidr_block], var.additional_allowed_cidr_blocks))
}

resource "aws_db_subnet_group" "primary" {
  provider    = aws.primary
  name        = local.primary_cluster_id
  description = "Private database subnets for ${local.primary_cluster_id}"
  subnet_ids  = local.primary_subnet_ids
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = local.secondary_cluster_id
  description = "Private database subnets for ${local.secondary_cluster_id}"
  subnet_ids  = local.secondary_subnet_ids
}

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name        = "${local.primary_cluster_id}-aurora"
  description = "Aurora PostgreSQL access for ${local.primary_cluster_id}"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.secondary_cluster_id}-aurora"
  description = "Aurora PostgreSQL access for ${local.secondary_cluster_id}"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider          = aws.primary
  for_each          = local.primary_allowed_cidrs
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider                     = aws.primary
  for_each                     = toset(var.primary_allowed_security_group_ids)
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from security group ${each.value}"
}

resource "aws_vpc_security_group_egress_rule" "primary_all" {
  provider          = aws.primary
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All egress"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider          = aws.secondary
  for_each          = local.secondary_allowed_cidrs
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider                     = aws.secondary
  for_each                     = toset(var.secondary_allowed_security_group_ids)
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from security group ${each.value}"
}

resource "aws_vpc_security_group_egress_rule" "secondary_all" {
  provider          = aws.secondary
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "All egress"
}
