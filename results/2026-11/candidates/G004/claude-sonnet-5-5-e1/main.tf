locals {
  identifier  = "${var.name}-${var.environment}"
  vpc_name    = "apps-${var.environment}"
  pg_family   = "aurora-postgresql${split(".", var.engine_version)[0]}"
  port        = 5432
  instance_ix = [for i in range(var.instances_per_region) : tostring(i)]

  tags = merge(var.tags, {
    Service     = var.name
    Environment = var.environment
    ManagedBy   = "opentofu"
    DataClass   = "customer-payment"
  })
}

# ---------------------------------------------------------------------------
# Network lookups (VPCs and database subnets are owned by the network team)
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
  tags = { Name = local.vpc_name }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = local.vpc_name }
}

data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  tags = { tier = "database" }
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
  name       = local.identifier
  subnet_ids = data.aws_subnets.primary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary.ids) >= 2
      error_message = "Fewer than two subnets tagged tier=database were found in the primary region VPC."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = local.identifier
  subnet_ids = data.aws_subnets.secondary.ids

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary.ids) >= 2
      error_message = "Fewer than two subnets tagged tier=database were found in the secondary region VPC."
    }
  }
}

# ---------------------------------------------------------------------------
# Security groups: PostgreSQL only from the named client security groups
# ---------------------------------------------------------------------------

resource "aws_security_group" "primary" {
  name_prefix = "${local.identifier}-db-"
  description = "Aurora PostgreSQL ${local.identifier}"
  vpc_id      = data.aws_vpc.primary.id

  tags = { Name = "${local.identifier}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.identifier}-db-"
  description = "Aurora PostgreSQL ${local.identifier}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = { Name = "${local.identifier}-db" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each = toset(var.allowed_security_group_ids.primary)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  description                  = "PostgreSQL from client security group"
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider = aws.secondary
  for_each = toset(var.allowed_security_group_ids.secondary)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
  description                  = "PostgreSQL from client security group"
}

# ---------------------------------------------------------------------------
# Encryption: customer-managed KMS key per region (a cross-region replica
# cannot use the primary region's key)
# ---------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  description             = "Aurora ${local.identifier} (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora ${local.identifier} (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.identifier}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}

# ---------------------------------------------------------------------------
# Parameter groups: require TLS for every connection
# ---------------------------------------------------------------------------

resource "aws_rds_cluster_parameter_group" "primary" {
  name_prefix = "${local.identifier}-"
  family      = local.pg_family
  description = "Aurora ${local.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.identifier}-"
  family      = local.pg_family
  description = "Aurora ${local.identifier}"

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global; shared by both regions)
# ---------------------------------------------------------------------------

resource "aws_iam_role" "monitoring" {
  name_prefix = "${local.identifier}-rds-mon-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "monitoring.rds.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
