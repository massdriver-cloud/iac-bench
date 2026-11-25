# The network team owns the VPCs and the database subnets. This module only
# looks them up: VPC by Name tag, database subnets by tier = database.

data "aws_vpc" "primary" {
  provider = aws.primary

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

data "aws_subnets" "primary_database" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
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
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.primary_cluster_id
  description = "Database subnets (tier=database) for ${local.primary_cluster_id}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.primary_region} has fewer than 2 subnets tagged tier=database. Aurora needs subnets in at least 2 Availability Zones."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.secondary_cluster_id
  description = "Database subnets (tier=database) for ${local.secondary_cluster_id}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.secondary_region} has fewer than 2 subnets tagged tier=database. Aurora needs subnets in at least 2 Availability Zones."
    }
  }
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-db"
  description = "PostgreSQL access to ${local.primary_cluster_id}"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-db"
  description = "PostgreSQL access to ${local.secondary_cluster_id}"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider = aws.primary
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider = aws.primary
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(var.allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL from ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  from_port                    = 5432
  to_port                      = 5432
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from security group ${each.value}"
}
