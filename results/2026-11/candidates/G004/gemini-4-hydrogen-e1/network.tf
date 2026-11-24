resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-primary"
  description = "Private database subnets for ${local.name_prefix} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_db.ids

  tags = {
    Name = "${local.name_prefix}-primary"
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary"
  description = "Private database subnets for ${local.name_prefix} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_db.ids

  tags = {
    Name = "${local.name_prefix}-secondary"
  }
}

resource "aws_security_group" "primary" {
  name_prefix            = "${local.name_prefix}-aurora-"
  description            = "Least-privilege ingress for ${local.name_prefix} Aurora PostgreSQL in ${var.primary_region}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true
  egress                 = []

  tags = {
    Name = "${local.name_prefix}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from EKS/service security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(local.primary_allowed_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from allowed CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name_prefix            = "${local.name_prefix}-aurora-"
  description            = "Least-privilege ingress for ${local.name_prefix} Aurora PostgreSQL in ${var.secondary_region}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true
  egress                 = []

  tags = {
    Name = "${local.name_prefix}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from EKS/service security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_allowed_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from allowed CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value
}
