resource "aws_db_subnet_group" "primary" {
  provider    = aws
  name        = "${local.name_prefix}-primary-subnets"
  description = "Database subnet group for ${local.name_prefix} primary cluster"
  subnet_ids  = data.aws_subnets.primary.ids

  tags = local.common_tags
}

resource "aws_security_group" "primary" {
  provider    = aws
  name        = "${local.name_prefix}-primary-db-sg"
  description = "Security group for ${local.name_prefix} primary Aurora cluster"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL access from primary VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.primary.cidr_block], var.allowed_cidr_blocks)
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-primary-db-sg"
    }
  )
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-subnets"
  description = "Database subnet group for ${local.name_prefix} secondary cluster"
  subnet_ids  = data.aws_subnets.secondary.ids

  tags = local.common_tags
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-db-sg"
  description = "Security group for ${local.name_prefix} secondary Aurora cluster"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL access from secondary VPC"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.secondary.cidr_block], var.allowed_cidr_blocks)
  }

  egress {
    description = "Allow all egress"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(
    local.common_tags,
    {
      Name = "${local.name_prefix}-secondary-db-sg"
    }
  )
}
