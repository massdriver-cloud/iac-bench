# VPC and Subnet data lookups for pre-existing network topology

data "aws_vpc" "primary" {
  tags = {
    Name = local.vpc_name
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags = {
    Name = local.vpc_name
  }
}

data "aws_subnets" "primary_database" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = {
    tier = "database"
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = {
    tier = "database"
  }
}

# DB Subnet Groups

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_prefix}-primary"
  description = "Database subnet group for ${var.service_name} primary cluster in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary"
  description = "Database subnet group for ${var.service_name} secondary cluster in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids
}

# Database Security Groups

resource "aws_security_group" "primary" {
  name        = "${local.name_prefix}-primary-rds"
  description = "Security group for ${var.service_name} Aurora PostgreSQL primary cluster"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL traffic from primary VPC services"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [var.allowed_cidr_blocks] : []
    content {
      description = "PostgreSQL traffic from allowed CIDR blocks"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ingress.value
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_security_group_ids) > 0 ? [var.allowed_security_group_ids] : []
    content {
      description     = "PostgreSQL traffic from allowed security groups"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = ingress.value
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-primary-rds-sg"
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-rds"
  description = "Security group for ${var.service_name} Aurora PostgreSQL secondary cluster"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL traffic from secondary VPC services"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }

  dynamic "ingress" {
    for_each = length(var.allowed_cidr_blocks) > 0 ? [var.allowed_cidr_blocks] : []
    content {
      description = "PostgreSQL traffic from allowed CIDR blocks"
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = ingress.value
    }
  }

  dynamic "ingress" {
    for_each = length(var.allowed_secondary_security_group_ids) > 0 ? [var.allowed_secondary_security_group_ids] : []
    content {
      description     = "PostgreSQL traffic from allowed secondary security groups"
      from_port       = 5432
      to_port         = 5432
      protocol        = "tcp"
      security_groups = ingress.value
    }
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-secondary-rds-sg"
  }
}
