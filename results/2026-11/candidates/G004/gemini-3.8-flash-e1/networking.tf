data "aws_vpc" "primary" {
  id = var.primary_vpc_id

  dynamic "filter" {
    for_each = var.primary_vpc_id == null ? [1] : []
    content {
      name   = "tag:Name"
      values = ["apps-${var.environment}"]
    }
  }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  id       = var.secondary_vpc_id

  dynamic "filter" {
    for_each = var.secondary_vpc_id == null ? [1] : []
    content {
      name   = "tag:Name"
      values = ["apps-${var.environment}"]
    }
  }
}

data "aws_subnets" "secondary" {
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

resource "aws_db_subnet_group" "primary" {
  name        = "${var.name}-primary-db-subnets"
  description = "Aurora PostgreSQL database subnet group for ${var.name} in primary region"
  subnet_ids  = local.primary_subnet_ids

  tags = local.primary_tags
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-secondary-db-subnets"
  description = "Aurora PostgreSQL database subnet group for ${var.name} in secondary region"
  subnet_ids  = local.secondary_subnet_ids

  tags = local.secondary_tags
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-primary-db"
  description = "Security group for Aurora PostgreSQL cluster ${var.name} in primary region"
  vpc_id      = local.primary_vpc_id

  ingress {
    description     = "PostgreSQL inbound traffic"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = local.primary_allowed_cidrs
    security_groups = var.allowed_security_group_ids
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.primary_tags,
    {
      Name = "${var.name}-primary-db"
    }
  )
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-secondary-db"
  description = "Security group for Aurora PostgreSQL cluster ${var.name} in secondary region"
  vpc_id      = local.secondary_vpc_id

  ingress {
    description     = "PostgreSQL inbound traffic"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    cidr_blocks     = local.secondary_allowed_cidrs
    security_groups = var.secondary_allowed_security_group_ids
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.secondary_tags,
    {
      Name = "${var.name}-secondary-db"
    }
  )
}
