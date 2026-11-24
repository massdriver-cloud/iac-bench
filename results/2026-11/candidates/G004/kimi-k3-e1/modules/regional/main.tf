terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
}

# -----------------------------------------------------------------------------
# Regional foundation for one Aurora cluster: network discovery, DB subnet
# group, security group, KMS key and cluster parameter group. Instantiated
# once per region by the root module with a different provider each time.
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# --- Network discovery -------------------------------------------------------
#
# The network team owns exactly one VPC per environment per region (tagged,
# by default, Name = "apps-prod") and pre-creates the private database
# subnets inside it (tagged tier = "database"). All lookups use plural data
# sources, which return an empty result instead of erroring, so a missing
# network never produces an obscure provider error: the discovered values
# are surfaced through the root module's `discovered_network` output.

data "aws_vpcs" "selected" {
  tags = var.vpc_tags
}

locals {
  # If a lookup ever matches more than one VPC, pick deterministically.
  vpc_ids = sort(data.aws_vpcs.selected.ids)
  vpc_id  = length(local.vpc_ids) > 0 ? local.vpc_ids[0] : null
}

data "aws_subnets" "database" {
  dynamic "filter" {
    for_each = local.vpc_id == null ? [] : [local.vpc_id]
    content {
      name   = "vpc-id"
      values = [filter.value]
    }
  }

  tags = var.subnet_tags
}

data "aws_vpc" "selected" {
  count = local.vpc_id == null ? 0 : 1
  id    = local.vpc_id
}

locals {
  # Never fall back to subnets outside the selected VPC: if the VPC was not
  # found, the discovered subnet list stays empty.
  database_subnet_ids = local.vpc_id == null ? [] : sort(data.aws_subnets.database.ids)
  vpc_cidr_block      = try(data.aws_vpc.selected[0].cidr_block, null)

  # Default posture: everything inside the environment VPC (i.e. the EKS
  # workloads) may reach the database port. Callers can tighten this with
  # explicit CIDR blocks and/or source security groups.
  ingress_cidr_blocks = var.allowed_cidr_blocks != null ? var.allowed_cidr_blocks : (
    local.vpc_cidr_block != null ? [local.vpc_cidr_block] : []
  )
}

# --- Encryption at rest ------------------------------------------------------
#
# KMS keys are region-scoped, so each regional cluster gets its own customer
# managed key. The policy delegates to IAM, which is what allows RDS and
# Secrets Manager to create the grants they need.

resource "aws_kms_key" "this" {
  description             = "${var.name} Aurora PostgreSQL encryption key"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EnableIamPermissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.name}-aurora"
  target_key_id = aws_kms_key.this.key_id
}

# --- Database subnet group ---------------------------------------------------

resource "aws_db_subnet_group" "this" {
  name        = "${var.name}-database"
  description = "Private database subnets for ${var.name}"
  subnet_ids  = local.database_subnet_ids
}

# --- Security group ----------------------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.name}-aurora"
  description = "Access to the ${var.name} Aurora PostgreSQL cluster"
  vpc_id      = local.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "cidr" {
  for_each = toset(local.ingress_cidr_blocks)

  security_group_id = aws_security_group.this.id
  description       = "PostgreSQL from ${each.value}"
  cidr_ipv4         = each.value
  from_port         = var.port
  to_port           = var.port
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "security_group" {
  for_each = toset(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "PostgreSQL from security group ${each.value}"
  referenced_security_group_id = each.value
  from_port                    = var.port
  to_port                      = var.port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "all_ipv4" {
  security_group_id = aws_security_group.this.id
  description       = "Allow all outbound IPv4"
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- Cluster parameter group -------------------------------------------------
#
# Parameter groups are region-scoped, so each region gets an identical one.
# The merged parameter set always includes rds.force_ssl = 1.

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-cluster"
  family      = var.parameter_group_family
  description = "${var.name} Aurora PostgreSQL cluster parameters"

  dynamic "parameter" {
    for_each = var.cluster_parameters
    content {
      name  = parameter.key
      value = parameter.value
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}
