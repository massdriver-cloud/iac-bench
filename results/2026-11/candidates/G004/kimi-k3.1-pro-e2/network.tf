data "aws_subnets" "primary" {
  provider = aws.primary
  count    = var.primary_db_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  count    = var.secondary_db_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  filter {
    name   = "map-public-ip-on-launch"
    values = ["false"]
  }
}

locals {
  primary_db_subnet_ids   = var.primary_db_subnet_ids != null ? var.primary_db_subnet_ids : data.aws_subnets.primary[0].ids
  secondary_db_subnet_ids = var.secondary_db_subnet_ids != null ? var.secondary_db_subnet_ids : data.aws_subnets.secondary[0].ids
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = "${var.name}-aurora-primary"
  description = "Private tier=database subnets for ${var.name} in ${var.primary_region}"
  subnet_ids  = local.primary_db_subnet_ids

  lifecycle {
    precondition {
      condition     = length(distinct(local.primary_db_subnet_ids)) >= 2
      error_message = "No usable primary subnet set: provide at least two subnets or tag at least two private subnets in different AZs with tier=database."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-aurora-secondary"
  description = "Private tier=database subnets for ${var.name} in ${var.secondary_region}"
  subnet_ids  = local.secondary_db_subnet_ids

  lifecycle {
    precondition {
      condition     = length(distinct(local.secondary_db_subnet_ids)) >= 2
      error_message = "No usable secondary subnet set: provide at least two subnets or tag at least two private subnets in different AZs with tier=database."
    }
  }
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name                   = "${var.name}-aurora-primary"
  description            = "PostgreSQL access to ${var.name}; no public ingress"
  vpc_id                 = var.primary_vpc_id
  revoke_rules_on_delete = true

  lifecycle {
    precondition {
      condition     = length(var.primary_application_security_group_ids) + length(var.primary_application_cidr_blocks) > 0
      error_message = "Configure at least one primary application security group or CIDR so the database is not unreachable."
    }
    precondition {
      condition     = !contains(var.primary_application_cidr_blocks, "0.0.0.0/0")
      error_message = "The primary database must not allow ingress from 0.0.0.0/0."
    }
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name                   = "${var.name}-aurora-secondary"
  description            = "PostgreSQL access to ${var.name} after regional recovery; no public ingress"
  vpc_id                 = var.secondary_vpc_id
  revoke_rules_on_delete = true

  lifecycle {
    precondition {
      condition     = length(var.secondary_application_security_group_ids) + length(var.secondary_application_cidr_blocks) > 0
      error_message = "Configure at least one secondary application security group or CIDR so the recovered database is not unreachable."
    }
    precondition {
      condition     = !contains(var.secondary_application_cidr_blocks, "0.0.0.0/0")
      error_message = "The secondary database must not allow ingress from 0.0.0.0/0."
    }
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_security_groups" {
  provider = aws.primary
  for_each = toset(var.primary_application_security_group_ids)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  description                  = "PostgreSQL from EKS workload security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidrs" {
  provider = aws.primary
  for_each = toset(var.primary_application_cidr_blocks)

  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  description       = "PostgreSQL from approved private application range ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_security_groups" {
  provider = aws.secondary
  for_each = toset(var.secondary_application_security_group_ids)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  description                  = "PostgreSQL from EKS workload security group ${each.value}"
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidrs" {
  provider = aws.secondary
  for_each = toset(var.secondary_application_cidr_blocks)

  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = local.port
  to_port           = local.port
  description       = "PostgreSQL from approved private application range ${each.value}"
}

resource "aws_iam_role" "rds_monitoring" {
  provider = aws.primary

  name        = "${var.name}-rds-enhanced-monitoring"
  description = "Allows both regional Aurora clusters to publish enhanced operating-system metrics"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.${data.aws_partition.primary.dns_suffix}"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  provider = aws.primary

  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${data.aws_partition.primary.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
