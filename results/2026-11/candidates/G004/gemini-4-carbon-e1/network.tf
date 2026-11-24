# -----------------------------------------------------------------------------
# Multi-Region VPC & Private Database Subnet Discovery
# -----------------------------------------------------------------------------

data "aws_vpc" "primary" {
  region = var.primary_region
  state  = "available"

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  region = var.secondary_region
  state  = "available"

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_database" {
  region = var.primary_region

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary_database" {
  region = var.secondary_region

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnet" "primary_database" {
  for_each = toset(data.aws_subnets.primary_database.ids)
  region   = var.primary_region
  id       = each.value
}

data "aws_subnet" "secondary_database" {
  for_each = toset(data.aws_subnets.secondary_database.ids)
  region   = var.secondary_region
  id       = each.value
}

# -----------------------------------------------------------------------------
# DB Subnet Groups (Validated Multi-AZ & Private)
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  region      = var.primary_region
  name        = "${local.primary_cluster_id}-subnets"
  description = "Private database subnets for ${var.service_name} (${local.env_short}) in ${var.primary_region}"
  subnet_ids  = sort(data.aws_subnets.primary_database.ids)

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-subnets"
  })

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.primary_database : s.availability_zone])) >= 2
      error_message = "Primary VPC ${local.vpc_name} in ${var.primary_region} must contain 'tier = database' subnets across at least 2 Availability Zones."
    }

    precondition {
      condition     = alltrue([for s in data.aws_subnet.primary_database : !s.map_public_ip_on_launch])
      error_message = "All 'tier = database' subnets in ${var.primary_region} (${local.vpc_name}) must be private (map_public_ip_on_launch = false)."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  region      = var.secondary_region
  name        = "${local.secondary_cluster_id}-subnets"
  description = "Private database subnets for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"
  subnet_ids  = sort(data.aws_subnets.secondary_database.ids)

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-subnets"
  })

  lifecycle {
    precondition {
      condition     = length(distinct([for s in data.aws_subnet.secondary_database : s.availability_zone])) >= 2
      error_message = "Secondary VPC ${local.vpc_name} in ${var.secondary_region} must contain 'tier = database' subnets across at least 2 Availability Zones."
    }

    precondition {
      condition     = alltrue([for s in data.aws_subnet.secondary_database : !s.map_public_ip_on_launch])
      error_message = "All 'tier = database' subnets in ${var.secondary_region} (${local.vpc_name}) must be private (map_public_ip_on_launch = false)."
    }
  }
}

# -----------------------------------------------------------------------------
# Regional Database & EKS Client Security Groups
# -----------------------------------------------------------------------------

resource "aws_security_group" "db_primary" {
  region                 = var.primary_region
  name                   = "${local.primary_cluster_id}-db"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${local.env_short}) in ${var.primary_region}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-db"
  })
}

resource "aws_security_group" "client_primary" {
  region                 = var.primary_region
  name                   = "${local.primary_cluster_id}-db-client"
  description            = "Attach to EKS pods or node groups in ${var.primary_region} requiring PostgreSQL access to ${var.service_name}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-db-client"
  })
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_client_sg" {
  region                       = var.primary_region
  security_group_id            = aws_security_group.db_primary.id
  referenced_security_group_id = aws_security_group.client_primary.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from dedicated ${var.service_name} client security group"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "client_primary_to_db" {
  region                       = var.primary_region
  security_group_id            = aws_security_group.client_primary.id
  referenced_security_group_id = aws_security_group.db_primary.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow outbound PostgreSQL to ${var.service_name} Aurora cluster"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_allowed_sgs" {
  for_each = toset(var.allowed_security_group_ids.primary)

  region                       = var.primary_region
  security_group_id            = aws_security_group.db_primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from caller-specified security group ${each.value}"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_from_allowed_cidrs" {
  for_each = toset(var.allowed_cidr_blocks.primary)

  region            = var.primary_region
  security_group_id = aws_security_group.db_primary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL from caller-specified CIDR ${each.value}"

  tags = local.tags
}

resource "aws_security_group" "db_secondary" {
  region                 = var.secondary_region
  name                   = "${local.secondary_cluster_id}-db"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${local.env_short}) in ${var.secondary_region}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-db"
  })
}

resource "aws_security_group" "client_secondary" {
  region                 = var.secondary_region
  name                   = "${local.secondary_cluster_id}-db-client"
  description            = "Attach to EKS pods or node groups in ${var.secondary_region} requiring PostgreSQL access to ${var.service_name}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-db-client"
  })
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_client_sg" {
  region                       = var.secondary_region
  security_group_id            = aws_security_group.db_secondary.id
  referenced_security_group_id = aws_security_group.client_secondary.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from dedicated ${var.service_name} client security group"

  tags = local.tags
}

resource "aws_vpc_security_group_egress_rule" "client_secondary_to_db" {
  region                       = var.secondary_region
  security_group_id            = aws_security_group.client_secondary.id
  referenced_security_group_id = aws_security_group.db_secondary.id
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow outbound PostgreSQL to ${var.service_name} Aurora cluster"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_allowed_sgs" {
  for_each = toset(var.allowed_security_group_ids.secondary)

  region                       = var.secondary_region
  security_group_id            = aws_security_group.db_secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "Allow PostgreSQL from caller-specified security group ${each.value}"

  tags = local.tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_from_allowed_cidrs" {
  for_each = toset(var.allowed_cidr_blocks.secondary)

  region            = var.secondary_region
  security_group_id = aws_security_group.db_secondary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "Allow PostgreSQL from caller-specified CIDR ${each.value}"

  tags = local.tags
}
