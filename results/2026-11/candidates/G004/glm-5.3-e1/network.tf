# ---------------------------------------------------------------------------
# Database subnet groups (built from the network team's private subnets)
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name}-db-subnets"
  description = "Private database subnets for the ${local.name} Aurora cluster (${var.primary_region})."
  subnet_ids  = local.primary_subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.primary_subnet_ids) >= 2
      error_message = "Aurora needs database subnets in at least two Availability Zones; found ${length(local.primary_subnet_ids)} matching subnets in ${var.primary_region}."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-db-subnets"
  description = "Private database subnets for the ${local.name} Aurora cluster (${var.secondary_region})."
  subnet_ids  = local.secondary_subnet_ids

  lifecycle {
    precondition {
      condition     = length(local.secondary_subnet_ids) >= 2
      error_message = "Aurora needs database subnets in at least two Availability Zones; found ${length(local.secondary_subnet_ids)} matching subnets in ${var.secondary_region}."
    }
  }
}

# ---------------------------------------------------------------------------
# Security groups (PostgreSQL ingress only, no public access)
# ---------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  name        = "${local.name}-aurora"
  description = "PostgreSQL ingress for the ${local.name} Aurora cluster in ${var.primary_region}."
  vpc_id      = data.aws_vpc.primary.id

  dynamic "ingress" {
    for_each = local.primary_ingress_cidrs
    content {
      description = "PostgreSQL from approved CIDR blocks"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.primary_allowed_security_group_ids
    content {
      description     = "PostgreSQL from approved security groups"
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-aurora"
  description = "PostgreSQL ingress for the ${local.name} Aurora cluster in ${var.secondary_region}."
  vpc_id      = data.aws_vpc.secondary.id

  dynamic "ingress" {
    for_each = local.secondary_ingress_cidrs
    content {
      description = "PostgreSQL from approved CIDR blocks"
      from_port   = var.port
      to_port     = var.port
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
    }
  }

  dynamic "ingress" {
    for_each = var.secondary_allowed_security_group_ids
    content {
      description     = "PostgreSQL from approved security groups"
      from_port       = var.port
      to_port         = var.port
      protocol        = "tcp"
      security_groups = [ingress.value]
    }
  }

  tags = {
    Name = "${local.name}-aurora"
  }
}
