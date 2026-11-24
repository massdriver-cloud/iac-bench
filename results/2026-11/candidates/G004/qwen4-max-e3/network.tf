# Private database subnets discovered by tag; one subnet group per region.

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.name
  description = "Database subnets for ${local.name} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.database_primary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_primary.ids) >= 2
      error_message = "Expected at least 2 subnets tagged tier=database in VPC ${local.vpc_name} (${var.primary_region}); ask the network team."
    }
  }

  tags = {
    Name = local.name
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  description = "Database subnets for ${local.name} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.database_secondary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_secondary.ids) >= 2
      error_message = "Expected at least 2 subnets tagged tier=database in VPC ${local.vpc_name} (${var.secondary_region}); ask the network team."
    }
  }

  tags = {
    Name = local.name
  }
}

# Only workloads inside the environment VPC (the EKS nodes/pods) may reach
# Postgres. No egress rules: the database never initiates connections.

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL for ${local.name}: 5432 from within ${local.vpc_name} only"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL for ${local.name}: 5432 from within ${local.vpc_name} only"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }

  tags = {
    Name = "${local.name}-aurora"
  }
}
