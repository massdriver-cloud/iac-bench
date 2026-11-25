resource "aws_db_subnet_group" "primary" {
  name        = "${var.name}-primary"
  description = "Aurora database subnet group for ${var.name} in primary region"
  subnet_ids  = local.primary_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary"
      Region = var.primary_region
    }
  )
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-secondary"
  description = "Aurora database subnet group for ${var.name} in secondary region"
  subnet_ids  = local.secondary_subnet_ids

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary"
      Region = var.secondary_region
    }
  )
}

resource "aws_security_group" "primary" {
  name_prefix = "${var.name}-primary-db-"
  description = "Security group for ${var.name} Aurora PostgreSQL cluster in primary region"
  vpc_id      = local.primary_vpc_id

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-primary-db"
      Region = var.primary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "primary_ingress_vpc" {
  count             = local.primary_vpc_cidr != null ? 1 : 0
  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = [local.primary_vpc_cidr]
  security_group_id = aws_security_group.primary.id
  description       = "Allow inbound PostgreSQL traffic from primary VPC CIDR"
}

resource "aws_security_group_rule" "primary_ingress_cidrs" {
  count             = length(var.allowed_cidr_blocks) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.primary.id
  description       = "Allow inbound PostgreSQL traffic from specified CIDRs"
}

resource "aws_security_group_rule" "primary_ingress_sg" {
  for_each                 = toset(var.primary_allowed_security_group_ids)
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.primary.id
  description              = "Allow inbound PostgreSQL traffic from security group ${each.value}"
}

resource "aws_security_group_rule" "primary_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.primary.id
  description       = "Allow outbound traffic"
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${var.name}-secondary-db-"
  description = "Security group for ${var.name} Aurora PostgreSQL cluster in secondary region"
  vpc_id      = local.secondary_vpc_id

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-secondary-db"
      Region = var.secondary_region
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "secondary_ingress_vpc" {
  provider          = aws.secondary
  count             = local.secondary_vpc_cidr != null ? 1 : 0
  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = [local.secondary_vpc_cidr]
  security_group_id = aws_security_group.secondary.id
  description       = "Allow inbound PostgreSQL traffic from secondary VPC CIDR"
}

resource "aws_security_group_rule" "secondary_ingress_cidrs" {
  provider          = aws.secondary
  count             = length(var.allowed_cidr_blocks) > 0 ? 1 : 0
  type              = "ingress"
  from_port         = var.port
  to_port           = var.port
  protocol          = "tcp"
  cidr_blocks       = var.allowed_cidr_blocks
  security_group_id = aws_security_group.secondary.id
  description       = "Allow inbound PostgreSQL traffic from specified CIDRs"
}

resource "aws_security_group_rule" "secondary_ingress_sg" {
  provider                 = aws.secondary
  for_each                 = toset(var.secondary_allowed_security_group_ids)
  type                     = "ingress"
  from_port                = var.port
  to_port                  = var.port
  protocol                 = "tcp"
  source_security_group_id = each.value
  security_group_id        = aws_security_group.secondary.id
  description              = "Allow inbound PostgreSQL traffic from security group ${each.value}"
}

resource "aws_security_group_rule" "secondary_egress" {
  provider          = aws.secondary
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.secondary.id
  description       = "Allow outbound traffic"
}
