# The network team owns one VPC per environment in each region and has already
# created the private database subnets. The module finds them by convention so
# nobody has to copy VPC or subnet IDs around.

# --- Primary region ---------------------------------------------------------

data "aws_vpc" "primary" {
  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "Expected at least two subnets tagged tier=database in VPC apps-${var.environment} in ${var.primary_region}."
    }
  }
}

resource "aws_db_subnet_group" "primary" {
  name        = local.cluster_identifiers.primary
  description = "Private database subnets for ${local.name} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary.ids
}

resource "aws_security_group" "primary" {
  name        = "${local.cluster_identifiers.primary}-aurora"
  description = "Aurora PostgreSQL ${local.name}: PostgreSQL in from approved client security groups only"
  vpc_id      = data.aws_vpc.primary.id

  # No egress rules: the database never needs to open connections.

  tags = {
    Name = "${local.cluster_identifiers.primary}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each = toset(var.client_security_group_ids.primary)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

# --- Secondary region -------------------------------------------------------

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "Expected at least two subnets tagged tier=database in VPC apps-${var.environment} in ${var.secondary_region}."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.cluster_identifiers.secondary
  description = "Private database subnets for ${local.name} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary.ids
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.cluster_identifiers.secondary}-aurora"
  description = "Aurora PostgreSQL ${local.name}: PostgreSQL in from approved client security groups only"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.cluster_identifiers.secondary}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider = aws.secondary
  for_each = toset(var.client_security_group_ids.secondary)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}
