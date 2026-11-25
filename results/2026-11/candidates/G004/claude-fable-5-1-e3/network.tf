locals {
  # If the caller didn't say who may connect, allow the VPC itself. The subnets
  # are private, so this is "anything in the environment's VPC" — a safe
  # starting point that callers should narrow to their EKS security group.
  primary_cidr_fallback   = length(var.primary_allowed_security_group_ids) == 0 && length(var.primary_allowed_cidr_blocks) == 0 ? [data.aws_vpc.primary.cidr_block] : []
  secondary_cidr_fallback = length(var.secondary_allowed_security_group_ids) == 0 && length(var.secondary_allowed_cidr_blocks) == 0 ? [data.aws_vpc.secondary.cidr_block] : []

  primary_allowed_cidrs   = concat(var.primary_allowed_cidr_blocks, local.primary_cidr_fallback)
  secondary_allowed_cidrs = concat(var.secondary_allowed_cidr_blocks, local.secondary_cidr_fallback)
}

############################################
# Primary region
############################################

resource "aws_db_subnet_group" "primary" {
  name        = local.name
  description = "Database subnets for ${local.name} in ${local.vpc_name}"
  subnet_ids  = data.aws_subnets.primary_database.ids
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL ${local.name}"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(local.primary_allowed_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}

############################################
# Secondary region
############################################

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  description = "Database subnets for ${local.name} in ${local.vpc_name}"
  subnet_ids  = data.aws_subnets.secondary_database.ids
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL ${local.name}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_allowed_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}
