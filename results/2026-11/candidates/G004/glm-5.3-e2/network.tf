# -----------------------------------------------------------------------------
# DB subnet groups (one per region). Aurora requires a cluster's instances to
# span at least two availability zones; the preconditions surface network
# problems as clear, actionable plan errors instead of RDS API failures.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  provider   = aws.primary
  name       = "${local.name}-${var.primary_region}-subnets"
  subnet_ids = local.primary_subnet_ids

  tags = {
    Name = "${local.name}-${var.primary_region}-subnets"
  }

  lifecycle {
    precondition {
      condition     = local.primary_vpc_id != null
      error_message = "No VPC named ${local.vpc_name} was found in ${var.primary_region}. Check the vpc_name variable, or provide subnet_ids[\"primary\"]."
    }

    precondition {
      condition     = length(local.primary_subnet_ids) >= 2
      error_message = "At least two subnets tagged tier = database are required in the ${local.vpc_name} VPC in ${var.primary_region} (found ${length(local.primary_subnet_ids)})."
    }

    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary_database : s.availability_zone])) >= 2
      error_message = "The database subnets for the primary cluster must span at least two availability zones."
    }

    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary_database : s.vpc_id])) <= 1
      error_message = "All database subnets used for the primary cluster must belong to the same VPC."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.name}-${var.secondary_region}-subnets"
  subnet_ids = local.secondary_subnet_ids

  tags = {
    Name = "${local.name}-${var.secondary_region}-subnets"
  }

  lifecycle {
    precondition {
      condition     = local.secondary_vpc_id != null
      error_message = "No VPC named ${local.vpc_name} was found in ${var.secondary_region}. Check the vpc_name variable, or provide subnet_ids[\"secondary\"]."
    }

    precondition {
      condition     = length(local.secondary_subnet_ids) >= 2
      error_message = "At least two subnets tagged tier = database are required in the ${local.vpc_name} VPC in ${var.secondary_region} (found ${length(local.secondary_subnet_ids)})."
    }

    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary_database : s.availability_zone])) >= 2
      error_message = "The database subnets for the secondary cluster must span at least two availability zones."
    }

    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary_database : s.vpc_id])) <= 1
      error_message = "All database subnets used for the secondary cluster must belong to the same VPC."
    }
  }
}

# -----------------------------------------------------------------------------
# Security groups for the clusters (one per region - security groups are
# region-scoped, so the failover region needs its own).
# -----------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name        = "${local.name}-${var.primary_region}-db"
  description = "Aurora PostgreSQL access for ${var.name} (${var.environment}) in ${var.primary_region}"
  vpc_id      = local.primary_vpc_id

  tags = {
    Name = "${local.name}-${var.primary_region}-db"
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-${var.secondary_region}-db"
  description = "Aurora PostgreSQL access for ${var.name} (${var.environment}) in ${var.secondary_region}"
  vpc_id      = local.secondary_vpc_id

  tags = {
    Name = "${local.name}-${var.secondary_region}-db"
  }
}

# Ingress from trusted security groups - typically the EKS node / cluster
# security groups of the service, referenced per region.

resource "aws_vpc_security_group_ingress_rule" "primary_from_security_groups" {
  provider = aws.primary
  count    = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from trusted security group ${var.allowed_security_group_ids[count.index]}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_security_groups" {
  provider = aws.secondary
  count    = length(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = var.secondary_allowed_security_group_ids[count.index]
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
  description                  = "PostgreSQL from trusted security group ${var.secondary_allowed_security_group_ids[count.index]}"
}

# Ingress from trusted CIDRs, including the VPC-CIDR fallback used when no
# security groups or CIDRs are configured (see locals.tf).

resource "aws_vpc_security_group_ingress_rule" "primary_from_cidrs" {
  provider = aws.primary
  count    = length(local.primary_ingress_cidrs)

  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = local.primary_ingress_cidrs[count.index]
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "PostgreSQL from trusted CIDR ${local.primary_ingress_cidrs[count.index]}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_cidrs" {
  provider = aws.secondary
  count    = length(local.secondary_ingress_cidrs)

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = local.secondary_ingress_cidrs[count.index]
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
  description       = "PostgreSQL from trusted CIDR ${local.secondary_ingress_cidrs[count.index]}"
}

# Egress is left open: the clusters push CloudWatch metrics, exported logs and
# enhanced-monitoring agent data to AWS endpoints, and restrictive egress is a
# network-team concern (VPC endpoints) rather than a database one.

resource "aws_vpc_security_group_egress_rule" "primary" {
  provider          = aws.primary
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all egress (CloudWatch metrics/logs, enhanced monitoring)"
}

resource "aws_vpc_security_group_egress_rule" "secondary" {
  provider          = aws.secondary
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
  description       = "Allow all egress (CloudWatch metrics/logs, enhanced monitoring)"
}
