############################################
# Network discovery — the network team owns the VPCs and database subnets
############################################

data "aws_caller_identity" "current" {
  provider = aws.primary
}

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

############################################
# Subnet groups
############################################

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.primary_cluster_id
  description = "Database subnets for ${local.name} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = { Name = local.primary_cluster_id }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "Expected at least two subnets tagged tier=database in VPC ${local.vpc_name} (${var.primary_region}); found ${length(data.aws_subnets.primary_database.ids)}. Aurora needs subnets in at least two AZs."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.secondary_cluster_id
  description = "Database subnets for ${local.name} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = { Name = local.secondary_cluster_id }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "Expected at least two subnets tagged tier=database in VPC ${local.vpc_name} (${var.secondary_region}); found ${length(data.aws_subnets.secondary_database.ids)}. Aurora needs subnets in at least two AZs."
    }
  }
}

############################################
# Security groups — PostgreSQL in, nothing out
############################################

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-db"
  description = "Aurora PostgreSQL ${local.name} (${var.primary_region})"
  vpc_id      = data.aws_vpc.primary.id

  tags = { Name = "${local.primary_cluster_id}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider = aws.primary
  for_each = toset(local.primary_ingress_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider = aws.primary
  for_each = toset(var.allowed_security_group_ids.primary)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-db"
  description = "Aurora PostgreSQL ${local.name} (${var.secondary_region})"
  vpc_id      = data.aws_vpc.secondary.id

  tags = { Name = "${local.secondary_cluster_id}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_ingress_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.allowed_security_group_ids.secondary)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
