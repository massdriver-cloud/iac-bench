resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-primary"
  description = "Private database subnets for ${local.name_prefix} in ${var.primary_region}."
  subnet_ids  = data.aws_subnets.primary_database.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_database.ids) >= 2
      error_message = "Expected at least 2 database subnets tagged tier=database in VPC apps-${var.environment} (${var.primary_region})."
    }
  }

  tags = {
    Name = "${local.name_prefix}-primary-subnet-group"
    Role = "primary"
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name_prefix}-secondary"
  description = "Private database subnets for ${local.name_prefix} in ${var.secondary_region}."
  subnet_ids  = data.aws_subnets.secondary_database.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_database.ids) >= 2
      error_message = "Expected at least 2 database subnets tagged tier=database in VPC apps-${var.environment} (${var.secondary_region})."
    }
  }

  tags = {
    Name = "${local.name_prefix}-secondary-subnet-group"
    Role = "secondary"
  }
}

resource "aws_security_group" "primary" {
  name                   = "${local.name_prefix}-aurora-primary"
  description            = "Least-privilege security group for ${local.name_prefix} Aurora PostgreSQL in ${var.primary_region}."
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name_prefix}-aurora-primary"
    Role = "primary"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL TLS ingress from EKS/application security group ${each.value}."
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(var.primary_allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL TLS ingress from allowed private CIDR ${each.value}."
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name                   = "${local.name_prefix}-aurora-secondary"
  description            = "Least-privilege security group for ${local.name_prefix} Aurora PostgreSQL in ${var.secondary_region}."
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.name_prefix}-aurora-secondary"
    Role = "secondary"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL TLS ingress from EKS/application security group ${each.value}."
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL TLS ingress from allowed private CIDR ${each.value}."
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}
