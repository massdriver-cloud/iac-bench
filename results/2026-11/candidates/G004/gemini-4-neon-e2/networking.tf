################################################################################
# Regional DB Subnet Groups (Private tier=database Subnets)
################################################################################

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = local.primary_cluster_id
  description = "Private database subnets in ${local.vpc_name} (${var.primary_region}) for ${local.name_prefix}"
  subnet_ids  = data.aws_subnets.primary_db.ids

  tags = {
    Name = local.primary_cluster_id
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary_db.ids) >= 2 && length(local.primary_azs) >= 2
      error_message = "Expected at least 2 private database subnets (tag tier=database) across >= 2 AZs in VPC '${local.vpc_name}' (${var.primary_region})."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.secondary_cluster_id
  description = "Private database subnets in ${local.vpc_name} (${var.secondary_region}) for ${local.name_prefix}"
  subnet_ids  = data.aws_subnets.secondary_db.ids

  tags = {
    Name = local.secondary_cluster_id
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary_db.ids) >= 2 && length(local.secondary_azs) >= 2
      error_message = "Expected at least 2 private database subnets (tag tier=database) across >= 2 AZs in VPC '${local.vpc_name}' (${var.secondary_region})."
    }
  }
}

################################################################################
# Regional Security Groups (Fail-Closed, Least-Privilege Ingress Only)
################################################################################

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.primary_cluster_id}-sg"
  description = "Least-privilege security group for Aurora PostgreSQL ${local.name_prefix} (${var.primary_region})"
  vpc_id      = data.aws_vpc.primary.id

  # Intentionally no default egress rule: databases do not require outbound internet access.
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.primary_cluster_id}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  provider = aws.primary
  for_each = toset(var.primary_allowed_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from EKS security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  provider = aws.primary
  for_each = toset(var.primary_allowed_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL from private CIDR ${each.value}"
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.secondary_cluster_id}-sg"
  description = "Least-privilege security group for Aurora PostgreSQL ${local.name_prefix} (${var.secondary_region})"
  vpc_id      = data.aws_vpc.secondary.id

  # Intentionally no default egress rule: databases do not require outbound internet access.
  revoke_rules_on_delete = true

  tags = {
    Name = "${local.secondary_cluster_id}-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from EKS security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider = aws.secondary
  for_each = toset(var.secondary_allowed_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL from private CIDR ${each.value}"
}
