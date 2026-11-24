locals {
  name          = "${var.service_name}-${var.environment}"
  database_name = coalesce(var.database_name, replace(var.service_name, "-", "_"))
  vpc_name      = "apps-${var.environment}"
  family        = "aurora-postgresql${split(".", var.engine_version)[0]}"

  common_tags = merge(var.tags, {
    Service            = var.service_name
    Environment        = var.environment
    ManagedBy          = "opentofu"
    DataClassification = "customer-payment"
  })

  log_exports = ["postgresql"]

  # Cluster parameters applied identically in both regions.
  cluster_parameters = {
    "rds.force_ssl"              = { value = "1", apply_method = "pending-reboot" }
    "ssl_min_protocol_version"   = { value = "TLSv1.2", apply_method = "pending-reboot" }
    "password_encryption"        = { value = "scram-sha-256", apply_method = "immediate" }
    "log_connections"            = { value = "1", apply_method = "immediate" }
    "log_disconnections"         = { value = "1", apply_method = "immediate" }
    "log_min_duration_statement" = { value = "1000", apply_method = "immediate" }
    "log_statement"              = { value = "ddl", apply_method = "immediate" }
  }
}

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# ---------------------------------------------------------------------------
# Network lookups (VPCs and subnets are owned by the network team)
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
  tags = { Name = local.vpc_name }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = { tier = "database" }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = local.vpc_name }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  tags = { tier = "database" }
}

resource "aws_db_subnet_group" "primary" {
  name        = local.name
  description = "Database subnets for ${local.name}"
  subnet_ids  = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name        = local.name
  description = "Database subnets for ${local.name}"
  subnet_ids  = data.aws_subnets.secondary.ids
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

locals {
  primary_default_to_vpc   = length(var.allowed_security_group_ids.primary) == 0 && length(var.allowed_cidr_blocks.primary) == 0
  secondary_default_to_vpc = length(var.allowed_security_group_ids.secondary) == 0 && length(var.allowed_cidr_blocks.secondary) == 0

  primary_cidrs   = local.primary_default_to_vpc ? [data.aws_vpc.primary.cidr_block] : var.allowed_cidr_blocks.primary
  secondary_cidrs = local.secondary_default_to_vpc ? [data.aws_vpc.secondary.cidr_block] : var.allowed_cidr_blocks.secondary
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL access for ${local.name}"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each          = toset(local.primary_cidrs)
  security_group_id = aws_security_group.primary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each                     = toset(var.allowed_security_group_ids.primary)
  security_group_id            = aws_security_group.primary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-aurora"
  description = "Aurora PostgreSQL access for ${local.name}"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  provider          = aws.secondary
  for_each          = toset(local.secondary_cidrs)
  security_group_id = aws_security_group.secondary.id
  description       = "PostgreSQL from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 5432
  to_port           = 5432
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  provider                     = aws.secondary
  for_each                     = toset(var.allowed_security_group_ids.secondary)
  security_group_id            = aws_security_group.secondary.id
  description                  = "PostgreSQL from ${each.value}"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = each.value
}
# No egress rules: Aurora does not need to initiate outbound connections.
