# ---------------------------------------------------------------------------
# Subnet groups and security groups, one set per region. Only PostgreSQL (5432)
# from inside the VPC (or the explicitly allowed sources) is permitted; nothing
# is ever reachable from outside the VPC.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.name
  description = "Private database subnets for ${local.name} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  description = "Private database subnets for ${local.name} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids
}

# --- Primary region ---------------------------------------------------------

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL ${local.name}: PostgreSQL from application sources only"
  vpc_id      = data.aws_vpc.primary.id

  tags = { Name = "${local.name}-aurora" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider = aws.primary
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider = aws.primary
  for_each = toset(local.primary_ingress_cidrs)

  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
}

# Aurora needs outbound only to AWS endpoints inside the VPC (e.g. Secrets
# Manager rotation, cross-region replication over the AWS backbone).
resource "aws_vpc_security_group_egress_rule" "primary_https" {
  provider = aws.primary

  security_group_id = aws_security_group.primary.id
  description       = "HTTPS to AWS services"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}

# --- Secondary region -------------------------------------------------------

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL ${local.name}: PostgreSQL from application sources only"
  vpc_id      = data.aws_vpc.secondary.id

  tags = { Name = "${local.name}-aurora" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(local.secondary_ingress_cidrs)

  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
}

resource "aws_vpc_security_group_egress_rule" "secondary_https" {
  provider = aws.secondary

  security_group_id = aws_security_group.secondary.id
  description       = "HTTPS to AWS services"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
}
