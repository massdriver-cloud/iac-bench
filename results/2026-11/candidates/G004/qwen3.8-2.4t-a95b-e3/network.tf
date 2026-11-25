# ---------------------------------------------------------------------------
# Subnet groups
#
# Aurora requires subnets in at least two Availability Zones; the network
# team provisions one database subnet per AZ, so each group spans three AZs.
# If subnets are missing or mis-tagged, planning still succeeds but RDS
# rejects the subnet group at apply time — check the tier=database tags first.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  provider = aws

  name        = local.stack
  description = "Private database subnets for ${var.name} (${var.environment}) in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_db.ids

  tags = {
    Name = local.stack
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.stack
  description = "Private database subnets for ${var.name} (${var.environment}) in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_db.ids

  tags = {
    Name = local.stack
  }
}

# ---------------------------------------------------------------------------
# Security groups
#
# The database is reachable only from inside the environment VPC (its CIDR is
# always allowed) plus any security groups/CIDRs the service explicitly adds —
# normally the EKS node or pod security groups of the owning service.
# ---------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  provider = aws

  name        = "${local.stack}-aurora"
  description = "Aurora PostgreSQL for ${var.name} (${var.environment}) - primary region"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name = "${local.stack}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.stack}-aurora"
  description = "Aurora PostgreSQL for ${var.name} (${var.environment}) - secondary region"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.stack}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "primary_ingress_cidr" {
  provider = aws

  type        = "ingress"
  description = "PostgreSQL from ${local.vpc_name} VPC plus approved CIDRs"
  from_port   = var.port
  to_port     = var.port
  protocol    = "tcp"

  security_group_id = aws_security_group.primary.id
  cidr_blocks       = concat([data.aws_vpc.primary.cidr_block], local.allowed_cidrs_primary)
}

resource "aws_security_group_rule" "secondary_ingress_cidr" {
  provider = aws.secondary

  type        = "ingress"
  description = "PostgreSQL from ${local.vpc_name} VPC plus approved CIDRs"
  from_port   = var.port
  to_port     = var.port
  protocol    = "tcp"

  security_group_id = aws_security_group.secondary.id
  cidr_blocks       = concat([data.aws_vpc.secondary.cidr_block], local.allowed_cidrs_secondary)
}

resource "aws_security_group_rule" "primary_ingress_security_groups" {
  provider = aws

  for_each = toset(local.allowed_sgs_primary)

  type        = "ingress"
  description = "PostgreSQL access for ${each.value}"
  from_port   = var.port
  to_port     = var.port
  protocol    = "tcp"

  security_group_id        = aws_security_group.primary.id
  source_security_group_id = each.value
}

resource "aws_security_group_rule" "secondary_ingress_security_groups" {
  provider = aws.secondary

  for_each = toset(local.allowed_sgs_secondary)

  type        = "ingress"
  description = "PostgreSQL access for ${each.value}"
  from_port   = var.port
  to_port     = var.port
  protocol    = "tcp"

  security_group_id        = aws_security_group.secondary.id
  source_security_group_id = each.value
}

resource "aws_security_group_rule" "primary_egress" {
  provider = aws

  type        = "egress"
  description = "All egress (instances sit in private subnets; needed for responses and AWS API paths)"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"

  security_group_id = aws_security_group.primary.id
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "secondary_egress" {
  provider = aws.secondary

  type        = "egress"
  description = "All egress (instances sit in private subnets; needed for responses and AWS API paths)"
  from_port   = 0
  to_port     = 0
  protocol    = "-1"

  security_group_id = aws_security_group.secondary.id
  cidr_blocks       = ["0.0.0.0/0"]
}
