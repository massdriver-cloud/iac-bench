resource "aws_db_subnet_group" "primary" {
  name        = "${var.name}-aurora"
  description = "Private database subnets for ${var.name} Aurora"
  subnet_ids  = local.primary_subnet_ids

  tags = {
    Name = "${var.name}-aurora"
  }

  lifecycle {
    precondition {
      condition     = length(local.primary_subnet_ids) >= 2
      error_message = "No usable database subnet set was found. Create at least two subnets in different Availability Zones tagged tier=database, or set primary_db_subnet_ids explicitly."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-aurora"
  description = "Private database subnets for ${var.name} Aurora disaster recovery"
  subnet_ids  = local.secondary_subnet_ids

  tags = {
    Name = "${var.name}-aurora"
  }

  lifecycle {
    precondition {
      condition     = length(local.secondary_subnet_ids) >= 2
      error_message = "No usable database subnet set was found. Create at least two subnets in different Availability Zones tagged tier=database, or set secondary_db_subnet_ids explicitly."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-aurora"
  description = "Private PostgreSQL access to ${var.name} Aurora"
  vpc_id      = var.primary_vpc_id

  tags = {
    Name = "${var.name}-aurora"
    Tier = "database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-aurora"
  description = "Private PostgreSQL access to ${var.name} Aurora disaster recovery"
  vpc_id      = var.secondary_vpc_id

  tags = {
    Name = "${var.name}-aurora"
    Tier = "database"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "primary_from_security_groups" {
  for_each = toset(var.primary_allowed_security_group_ids)

  type                     = "ingress"
  description              = "PostgreSQL from application security group ${each.value}"
  security_group_id        = aws_security_group.primary.id
  source_security_group_id = each.value
  from_port                = var.database_port
  to_port                  = var.database_port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "secondary_from_security_groups" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  type                     = "ingress"
  description              = "PostgreSQL from application security group ${each.value}"
  security_group_id        = aws_security_group.secondary.id
  source_security_group_id = each.value
  from_port                = var.database_port
  to_port                  = var.database_port
  protocol                 = "tcp"
}

resource "aws_security_group_rule" "primary_from_cidrs" {
  for_each = toset([for cidr in var.primary_allowed_cidr_blocks : cidr if !strcontains(cidr, ":")])

  type              = "ingress"
  description       = "PostgreSQL from approved private IPv4 network ${each.value}"
  security_group_id = aws_security_group.primary.id
  cidr_blocks       = [each.value]
  from_port         = var.database_port
  to_port           = var.database_port
  protocol          = "tcp"
}

resource "aws_security_group_rule" "secondary_from_cidrs" {
  provider = aws.secondary
  for_each = toset([for cidr in var.secondary_allowed_cidr_blocks : cidr if !strcontains(cidr, ":")])

  type              = "ingress"
  description       = "PostgreSQL from approved private IPv4 network ${each.value}"
  security_group_id = aws_security_group.secondary.id
  cidr_blocks       = [each.value]
  from_port         = var.database_port
  to_port           = var.database_port
  protocol          = "tcp"
}

resource "aws_security_group_rule" "primary_from_ipv6_cidrs" {
  for_each = toset([for cidr in var.primary_allowed_cidr_blocks : cidr if strcontains(cidr, ":")])

  type              = "ingress"
  description       = "PostgreSQL from approved private IPv6 network ${each.value}"
  security_group_id = aws_security_group.primary.id
  ipv6_cidr_blocks  = [each.value]
  from_port         = var.database_port
  to_port           = var.database_port
  protocol          = "tcp"
}

resource "aws_security_group_rule" "secondary_from_ipv6_cidrs" {
  provider = aws.secondary
  for_each = toset([for cidr in var.secondary_allowed_cidr_blocks : cidr if strcontains(cidr, ":")])

  type              = "ingress"
  description       = "PostgreSQL from approved private IPv6 network ${each.value}"
  security_group_id = aws_security_group.secondary.id
  ipv6_cidr_blocks  = [each.value]
  from_port         = var.database_port
  to_port           = var.database_port
  protocol          = "tcp"
}
