################################################################################
# Account Context
################################################################################

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

################################################################################
# Primary Region Network Discovery (Network-Team-Owned VPC & Database Subnets)
################################################################################

data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
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
}

data "aws_subnet" "primary_database" {
  for_each = toset(data.aws_subnets.primary_database.ids)
  id       = each.value
}

################################################################################
# Secondary Region Network Discovery (Network-Team-Owned VPC & Database Subnets)
################################################################################

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
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

data "aws_subnet" "secondary_database" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary_database.ids)
  id       = each.value
}

################################################################################
# DB Subnet Groups (Private Database Tier Only)
################################################################################

resource "aws_db_subnet_group" "primary" {
  name        = "${local.primary_cluster_id}-subnets"
  description = "Private database subnets (tier=database) for ${local.primary_cluster_id} in ${local.vpc_name}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = {
    Name = "${local.primary_cluster_id}-subnets"
    Role = "primary"
  }

  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "Primary VPC '${local.vpc_name}' in ${var.primary_region} must contain private database subnets (tag tier=database) across at least 2 Availability Zones."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-subnets"
  description = "Private database subnets (tier=database) for ${local.secondary_cluster_id} in ${local.vpc_name}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = {
    Name = "${local.secondary_cluster_id}-subnets"
    Role = "secondary"
  }

  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "Secondary VPC '${local.vpc_name}' in ${var.secondary_region} must contain private database subnets (tag tier=database) across at least 2 Availability Zones."
    }
  }
}

################################################################################
# Security Groups (Least-Privilege, Zero Public Ingress, No Blanket Egress)
################################################################################

resource "aws_security_group" "primary" {
  name        = "${local.primary_cluster_id}-sg"
  description = "Least-privilege PostgreSQL ingress for Aurora cluster ${local.primary_cluster_id}"
  vpc_id      = data.aws_vpc.primary.id

  revoke_rules_on_delete = true

  tags = {
    Name = "${local.primary_cluster_id}-sg"
    Role = "primary"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL TLS traffic from EKS security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_cidr" {
  for_each = toset(var.primary_allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL TLS traffic from private CIDR ${each.value}"
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-sg"
  description = "Least-privilege PostgreSQL ingress for Aurora cluster ${local.secondary_cluster_id}"
  vpc_id      = data.aws_vpc.secondary.id

  revoke_rules_on_delete = true

  tags = {
    Name = "${local.secondary_cluster_id}-sg"
    Role = "secondary"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL TLS traffic from EKS security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_cidr" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL TLS traffic from private CIDR ${each.value}"
}
