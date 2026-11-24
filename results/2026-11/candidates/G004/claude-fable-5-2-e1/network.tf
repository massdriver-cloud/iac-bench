###############################################################################
# Subnet groups: the network team's private database subnets in each region.
###############################################################################

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.cluster_ids.primary
  description = "Private database subnets of apps-${var.environment} for ${local.name}"
  subnet_ids  = data.aws_subnets.primary.ids

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary : s.availability_zone])) >= 2
      error_message = "VPC apps-${var.environment} in ${var.primary_region} needs subnets tagged tier = database in at least two availability zones."
    }
    precondition {
      condition     = alltrue([for s in data.aws_subnet.primary : !s.map_public_ip_on_launch])
      error_message = "Subnets tagged tier = database in ${var.primary_region} must be private (no public IP on launch)."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.cluster_ids.secondary
  description = "Private database subnets of apps-${var.environment} for ${local.name}"
  subnet_ids  = data.aws_subnets.secondary.ids

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary : s.availability_zone])) >= 2
      error_message = "VPC apps-${var.environment} in ${var.secondary_region} needs subnets tagged tier = database in at least two availability zones."
    }
    precondition {
      condition     = alltrue([for s in data.aws_subnet.secondary : !s.map_public_ip_on_launch])
      error_message = "Subnets tagged tier = database in ${var.secondary_region} must be private (no public IP on launch)."
    }
  }
}

###############################################################################
# Security groups.
#
# Per region the module creates:
#   * a database security group, attached to the cluster, with no outbound
#     rules and inbound PostgreSQL only from named sources;
#   * a client security group that services attach to their pods (EKS
#     "security groups for pods") to be let in. Membership of that group is the
#     network-level permission to talk to this database.
###############################################################################

# ---- primary region ---------------------------------------------------------

resource "aws_security_group" "db_primary" {
  provider = aws.primary

  name_prefix = "${local.name}-db-"
  description = "Aurora PostgreSQL cluster ${local.cluster_ids.primary}"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name = "${local.name}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "client_primary" {
  provider = aws.primary

  name_prefix = "${local.name}-db-client-"
  description = "Attach to workloads that need to connect to ${local.cluster_ids.primary}"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name = "${local.name}-db-client"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "client_primary_to_db" {
  provider = aws.primary

  security_group_id            = aws_security_group.client_primary.id
  description                  = "PostgreSQL to ${local.cluster_ids.primary}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = aws_security_group.db_primary.id
}

resource "aws_vpc_security_group_ingress_rule" "db_primary_from_client" {
  provider = aws.primary

  security_group_id            = aws_security_group.db_primary.id
  description                  = "PostgreSQL from the ${local.name} client security group"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = aws_security_group.client_primary.id
}

resource "aws_vpc_security_group_ingress_rule" "db_primary_from_sg" {
  provider = aws.primary
  for_each = toset(var.allowed_security_group_ids.primary)

  security_group_id            = aws_security_group.db_primary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "db_primary_from_cidr" {
  provider = aws.primary
  for_each = toset(var.allowed_cidr_blocks.primary)

  security_group_id = aws_security_group.db_primary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value
}

# ---- secondary region -------------------------------------------------------

resource "aws_security_group" "db_secondary" {
  provider = aws.secondary

  name_prefix = "${local.name}-db-"
  description = "Aurora PostgreSQL cluster ${local.cluster_ids.secondary}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.name}-db"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "client_secondary" {
  provider = aws.secondary

  name_prefix = "${local.name}-db-client-"
  description = "Attach to workloads that need to connect to ${local.cluster_ids.secondary}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.name}-db-client"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_egress_rule" "client_secondary_to_db" {
  provider = aws.secondary

  security_group_id            = aws_security_group.client_secondary.id
  description                  = "PostgreSQL to ${local.cluster_ids.secondary}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = aws_security_group.db_secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "db_secondary_from_client" {
  provider = aws.secondary

  security_group_id            = aws_security_group.db_secondary.id
  description                  = "PostgreSQL from the ${local.name} client security group"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = aws_security_group.client_secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "db_secondary_from_sg" {
  provider = aws.secondary
  for_each = toset(var.allowed_security_group_ids.secondary)

  security_group_id            = aws_security_group.db_secondary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  referenced_security_group_id = each.value
}

resource "aws_vpc_security_group_ingress_rule" "db_secondary_from_cidr" {
  provider = aws.secondary
  for_each = toset(var.allowed_cidr_blocks.secondary)

  security_group_id = aws_security_group.db_secondary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  cidr_ipv4         = each.value
}
