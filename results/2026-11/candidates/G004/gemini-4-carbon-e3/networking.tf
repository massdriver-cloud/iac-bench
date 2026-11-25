# -----------------------------------------------------------------------------
# Primary Region Database Subnet Group & Security Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  region      = var.primary_region
  name        = local.primary_cluster_id
  description = "Private database subnets (tier=database) for ${var.service_name} in ${local.vpc_name} (${var.primary_region})"
  subnet_ids  = sort(data.aws_subnets.primary_database.ids)

  tags = merge(local.tags, {
    Name   = local.primary_cluster_id
    region = var.primary_region
  })

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary_database : s.availability_zone])) >= 2
      error_message = "Private database subnets in ${local.vpc_name} (${var.primary_region}) must span at least 2 Availability Zones for Multi-AZ high availability."
    }
  }
}

resource "aws_security_group" "primary" {
  region                 = var.primary_region
  name                   = "${local.primary_cluster_id}-db"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${var.environment}) in ${var.primary_region}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-db"
    region = var.primary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_vpc_cidr" {
  count = local.enable_primary_vpc_cidr_ingress ? 1 : 0

  region            = var.primary_region
  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL access from workloads in ${local.vpc_name} VPC (${var.primary_region})"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = data.aws_vpc.primary.cidr_block

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-vpc-ingress"
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = toset(var.allowed_security_group_ids.primary)

  region                       = var.primary_region
  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL access from allowed EKS security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-sg-${each.value}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = toset(var.allowed_cidr_blocks.primary)

  region            = var.primary_region
  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL access from allowed CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-cidr-ingress"
  })
}

# -----------------------------------------------------------------------------
# Secondary Region Database Subnet Group & Security Group
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "secondary" {
  region      = var.secondary_region
  name        = local.secondary_cluster_id
  description = "Private database subnets (tier=database) for ${var.service_name} in ${local.vpc_name} (${var.secondary_region})"
  subnet_ids  = sort(data.aws_subnets.secondary_database.ids)

  tags = merge(local.tags, {
    Name   = local.secondary_cluster_id
    region = var.secondary_region
  })

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary_database : s.availability_zone])) >= 2
      error_message = "Private database subnets in ${local.vpc_name} (${var.secondary_region}) must span at least 2 Availability Zones for Multi-AZ high availability."
    }
  }
}

resource "aws_security_group" "secondary" {
  region                 = var.secondary_region
  name                   = "${local.secondary_cluster_id}-db"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${var.environment}) in ${var.secondary_region}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-db"
    region = var.secondary_region
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_vpc_cidr" {
  count = local.enable_secondary_vpc_cidr_ingress ? 1 : 0

  region            = var.secondary_region
  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL access from workloads in ${local.vpc_name} VPC (${var.secondary_region})"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = data.aws_vpc.secondary.cidr_block

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-vpc-ingress"
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  for_each = toset(var.allowed_security_group_ids.secondary)

  region                       = var.secondary_region
  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL access from allowed EKS security group ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = each.value

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-sg-${each.value}"
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  for_each = toset(var.allowed_cidr_blocks.secondary)

  region            = var.secondary_region
  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL access from allowed CIDR ${each.value}"
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  cidr_ipv4         = each.value

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-cidr-ingress"
  })
}
