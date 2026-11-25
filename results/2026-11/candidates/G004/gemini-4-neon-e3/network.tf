# ------------------------------------------------------------------------------
# Primary Region Networking (apps-<environment> VPC, tier=database subnets)
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = "${local.primary_cluster_id}-subnet-group"
  description = "Private database subnets (tier=database) in apps-${var.environment} (${var.primary_region})"
  subnet_ids  = data.aws_subnets.primary_database.ids

  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2
      error_message = "At least 2 database subnets across distinct Availability Zones (tagged tier=database) are required in VPC apps-${var.environment} (${var.primary_region})."
    }
  }

  tags = {
    Name = "${local.primary_cluster_id}-subnet-group"
  }
}

# Zero outbound egress rules by design: Aurora does not initiate outbound internet
# connections, minimizing exfiltration surface for customer and payment data.
resource "aws_security_group" "primary" {
  name                   = "${local.primary_cluster_id}-sg"
  description            = "Aurora PostgreSQL security group for ${local.primary_cluster_id}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.primary_cluster_id}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_sg" {
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  description                  = "Allow PostgreSQL from EKS/service security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = {
    Name = "${local.primary_cluster_id}-ingress-${each.value}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_cidr" {
  for_each = toset(var.primary_allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  description       = "Allow PostgreSQL from CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.primary_cluster_id}-ingress-cidr"
  }
}

# ------------------------------------------------------------------------------
# Secondary Region Networking (apps-<environment> VPC, tier=database subnets)
# ------------------------------------------------------------------------------

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-subnet-group"
  description = "Private database subnets (tier=database) in apps-${var.environment} (${var.secondary_region})"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2
      error_message = "At least 2 database subnets across distinct Availability Zones (tagged tier=database) are required in VPC apps-${var.environment} (${var.secondary_region})."
    }
  }

  tags = {
    Name = "${local.secondary_cluster_id}-subnet-group"
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name                   = "${local.secondary_cluster_id}-sg"
  description            = "Aurora PostgreSQL security group for ${local.secondary_cluster_id}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = "${local.secondary_cluster_id}-sg"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  description                  = "Allow PostgreSQL from EKS/service security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = {
    Name = "${local.secondary_cluster_id}-ingress-${each.value}"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_cidr" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  description       = "Allow PostgreSQL from CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = {
    Name = "${local.secondary_cluster_id}-ingress-cidr"
  }
}
