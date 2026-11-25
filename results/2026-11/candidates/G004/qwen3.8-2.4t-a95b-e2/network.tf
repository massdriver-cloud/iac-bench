resource "aws_db_subnet_group" "primary" {
  name        = "${local.prefix}-${var.primary_region}"
  description = "Database subnets in ${local.vpc_name} (${var.primary_region}) for ${local.prefix}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = {
    Name = local.prefix
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.prefix}-${var.secondary_region}"
  description = "Database subnets in ${local.vpc_name} (${var.secondary_region}) for ${local.prefix}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = {
    Name = local.prefix
  }
}

# Only the service's own VPC can reach the database: EKS workloads live in this
# VPC and reach AWS through IAM roles. No public access, anywhere.
resource "aws_security_group" "primary" {
  name        = "${local.prefix}-db"
  description = "Aurora PostgreSQL for ${var.service_name} (${var.environment}) in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL from the ${local.vpc_name} VPC"
    from_port   = local.engine_port
    to_port     = local.engine_port
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.primary.cidr_block], var.additional_ingress_cidr_blocks)
  }

  egress {
    description = "Within the ${local.vpc_name} VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  tags = {
    Name = "${local.prefix}-db"
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.prefix}-db"
  description = "Aurora PostgreSQL for ${var.service_name} (${var.environment}) in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL from the ${local.vpc_name} VPC"
    from_port   = local.engine_port
    to_port     = local.engine_port
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.secondary.cidr_block], var.additional_ingress_cidr_blocks)
  }

  egress {
    description = "Within the ${local.vpc_name} VPC only"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }

  tags = {
    Name = "${local.prefix}-db"
  }
}
