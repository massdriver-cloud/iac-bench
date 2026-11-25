resource "aws_db_subnet_group" "primary" {
  provider    = aws.primary
  name        = "${local.name_prefix}-${var.primary_region}-db-subnets"
  description = "Private database subnet group (tier=database) for ${local.name_prefix} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-db-subnets"
    Region = var.primary_region
  })
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-${var.secondary_region}-db-subnets"
  description = "Private database subnet group (tier=database) for ${local.name_prefix} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-db-subnets"
    Region = var.secondary_region
  })
}

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name        = "${local.name_prefix}-${var.primary_region}-aurora-sg"
  description = "Controls access to the ${local.name_prefix} Aurora PostgreSQL cluster in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-aurora-sg"
    Region = var.primary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider          = aws.primary
  for_each          = toset(local.primary_cidr_blocks)
  security_group_id = aws_security_group.primary.id
  description       = "Allow PostgreSQL TCP connections from CIDR ${each.value} in ${var.primary_region}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-cidr-${replace(each.value, "/", "-")}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider                     = aws.primary
  for_each                     = toset(local.primary_security_group_ids)
  security_group_id            = aws_security_group.primary.id
  description                  = "Allow PostgreSQL TCP connections from EKS/application security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-sg-${each.value}"
  })
}

resource "aws_vpc_security_group_egress_rule" "primary_self" {
  provider                     = aws.primary
  security_group_id            = aws_security_group.primary.id
  description                  = "Allow intra-cluster communication within the primary Aurora security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.primary.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-primary-self-egress"
  })
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-${var.secondary_region}-aurora-sg"
  description = "Controls access to the ${local.name_prefix} Aurora PostgreSQL cluster in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-aurora-sg"
    Region = var.secondary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider          = aws.secondary
  for_each          = toset(local.secondary_cidr_blocks)
  security_group_id = aws_security_group.secondary.id
  description       = "Allow PostgreSQL TCP connections from CIDR ${each.value} in ${var.secondary_region}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-cidr-${replace(each.value, "/", "-")}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider                     = aws.secondary
  for_each                     = toset(local.secondary_security_group_ids)
  security_group_id            = aws_security_group.secondary.id
  description                  = "Allow PostgreSQL TCP connections from EKS/application security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-sg-${each.value}"
  })
}

resource "aws_vpc_security_group_egress_rule" "secondary_self" {
  provider                     = aws.secondary
  security_group_id            = aws_security_group.secondary.id
  description                  = "Allow intra-cluster communication within the secondary Aurora security group"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.secondary.id

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-secondary-self-egress"
  })
}
