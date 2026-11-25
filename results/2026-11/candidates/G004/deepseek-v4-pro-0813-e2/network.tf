#
# Network discovery
#
# The network team owns one VPC per environment in each region. The VPCs are
# found by their Name tag, and the private database subnets are found by the
# `tier = database` tag.
#

data "aws_vpcs" "primary" {
  provider = aws.primary

  tags = {
    Name = var.environment
  }
}

data "aws_vpcs" "secondary" {
  provider = aws.secondary

  tags = {
    Name = var.environment
  }
}

locals {
  primary_vpc_id   = length(data.aws_vpcs.primary.ids) > 0 ? data.aws_vpcs.primary.ids[0] : ""
  secondary_vpc_id = length(data.aws_vpcs.secondary.ids) > 0 ? data.aws_vpcs.secondary.ids[0] : ""
}

data "aws_vpc" "primary_selected" {
  provider = aws.primary
  count    = local.primary_vpc_id != "" ? 1 : 0
  id       = local.primary_vpc_id
}

data "aws_vpc" "secondary_selected" {
  provider = aws.secondary
  count    = local.secondary_vpc_id != "" ? 1 : 0
  id       = local.secondary_vpc_id
}

data "aws_subnets" "primary" {
  provider = aws.primary
  count    = local.primary_vpc_id != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.primary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  count    = local.secondary_vpc_id != "" ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.secondary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary
  count    = local.primary_vpc_id != "" ? 1 : 0

  name       = "${local.prefix}-primary"
  subnet_ids = local.primary_subnet_ids

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-primary-subnet-group"
      Region = var.primary_region
    }
  )
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary
  count    = local.secondary_vpc_id != "" ? 1 : 0

  name       = "${local.prefix}-secondary"
  subnet_ids = local.secondary_subnet_ids

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-secondary-subnet-group"
      Region = var.secondary_region
    }
  )
}

resource "aws_security_group" "primary" {
  provider = aws.primary
  count    = local.primary_vpc_id != "" ? 1 : 0

  name        = "${local.prefix}-primary-aurora"
  description = "Aurora PostgreSQL primary access for ${var.service_name} (${var.environment})"
  vpc_id      = local.primary_vpc_id

  dynamic "ingress" {
    for_each = var.allow_vpc_cidr ? flatten(data.aws_vpc.primary_selected[*].cidr_block) : []

    content {
      description = "PostgreSQL from ${var.environment} VPC"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks

    content {
      description = "PostgreSQL from ${ingress.value}"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.primary_allowed_security_group_ids

    content {
      description     = "PostgreSQL from security group"
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description      = "Allow all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-primary-aurora"
      Region = var.primary_region
    }
  )
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary
  count    = local.secondary_vpc_id != "" ? 1 : 0

  name        = "${local.prefix}-secondary-aurora"
  description = "Aurora PostgreSQL secondary access for ${var.service_name} (${var.environment})"
  vpc_id      = local.secondary_vpc_id

  dynamic "ingress" {
    for_each = var.allow_vpc_cidr ? flatten(data.aws_vpc.secondary_selected[*].cidr_block) : []

    content {
      description = "PostgreSQL from ${var.environment} VPC"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.allowed_cidr_blocks

    content {
      description = "PostgreSQL from ${ingress.value}"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.secondary_allowed_security_group_ids

    content {
      description     = "PostgreSQL from security group"
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  egress {
    description      = "Allow all outbound"
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-secondary-aurora"
      Region = var.secondary_region
    }
  )
}