resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-primary"
  description = "Private database subnets for ${local.name_prefix} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = {
    Name = "${local.name_prefix}-primary"
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary"
  description = "Private database subnets for ${local.name_prefix} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = {
    Name = "${local.name_prefix}-secondary"
  }
}

resource "aws_security_group" "primary" {
  name                   = "${local.name_prefix}-aurora-primary"
  description            = "PostgreSQL ingress only for ${local.name_prefix} primary Aurora cluster"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name_prefix}-aurora-primary"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL TLS access from EKS/authorized security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(var.primary_allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL TLS access from authorized CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name                   = "${local.name_prefix}-aurora-secondary"
  description            = "PostgreSQL ingress only for ${local.name_prefix} secondary Aurora cluster"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name_prefix}-aurora-secondary"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL TLS access from EKS/authorized security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL TLS access from authorized CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}
