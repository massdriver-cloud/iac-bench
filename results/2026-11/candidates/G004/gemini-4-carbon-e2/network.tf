data "aws_vpc" "primary" {
  region = var.primary_region

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  region = var.secondary_region

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

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "VPC ${local.vpc_name} in ${var.primary_region} must have at least 2 private subnets tagged tier=database for Multi-AZ Aurora deployment."
    }
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

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "VPC ${local.vpc_name} in ${var.secondary_region} must have at least 2 private subnets tagged tier=database for Multi-AZ Aurora deployment."
    }
  }
}

resource "aws_db_subnet_group" "primary" {
  region      = var.primary_region
  name        = "${local.name_prefix}-${var.primary_region}"
  description = "Private database subnets for ${var.service_name} (${var.environment}) in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.primary_database.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.primary_region}"
  })
}

resource "aws_db_subnet_group" "secondary" {
  region      = var.secondary_region
  name        = "${local.name_prefix}-${var.secondary_region}"
  description = "Private database subnets for ${var.service_name} (${var.environment}) in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.secondary_database.ids

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-${var.secondary_region}"
  })
}

locals {
  explicit_primary_sgs     = coalesce(var.allowed_security_group_ids.primary, toset([]))
  explicit_secondary_sgs   = coalesce(var.allowed_security_group_ids.secondary, toset([]))
  explicit_primary_cidrs   = coalesce(var.allowed_cidr_blocks.primary, toset([]))
  explicit_secondary_cidrs = coalesce(var.allowed_cidr_blocks.secondary, toset([]))

  use_primary_vpc_cidr_fallback = (
    var.allow_vpc_cidr_fallback &&
    length(local.explicit_primary_sgs) == 0 &&
    length(local.explicit_primary_cidrs) == 0
  )

  use_secondary_vpc_cidr_fallback = (
    var.allow_vpc_cidr_fallback &&
    length(local.explicit_secondary_sgs) == 0 &&
    length(local.explicit_secondary_cidrs) == 0
  )
}

resource "aws_security_group" "primary" {
  region                 = var.primary_region
  name_prefix            = "${local.name_prefix}-aurora-"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${var.environment}) in ${var.primary_region}"
  vpc_id                 = data.aws_vpc.primary.id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-${var.primary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  region                 = var.secondary_region
  name_prefix            = "${local.name_prefix}-aurora-"
  description            = "Aurora PostgreSQL security group for ${var.service_name} (${var.environment}) in ${var.secondary_region}"
  vpc_id                 = data.aws_vpc.secondary.id
  revoke_rules_on_delete = true

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-${var.secondary_region}"
  })

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_sg" {
  for_each = local.explicit_primary_sgs

  region                       = var.primary_region
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "PostgreSQL TLS access from client security group ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_sg" {
  for_each = local.explicit_secondary_sgs

  region                       = var.secondary_region
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  description                  = "PostgreSQL TLS access from client security group ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_cidr" {
  for_each = local.explicit_primary_cidrs

  region            = var.primary_region
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "PostgreSQL TLS access from allowed CIDR ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_cidr" {
  for_each = local.explicit_secondary_cidrs

  region            = var.secondary_region
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = each.value
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "PostgreSQL TLS access from allowed CIDR ${each.value}"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "primary_vpc_fallback" {
  count = local.use_primary_vpc_cidr_fallback ? 1 : 0

  region            = var.primary_region
  security_group_id = aws_security_group.primary.id
  cidr_ipv4         = data.aws_vpc.primary.cidr_block
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "PostgreSQL TLS access from ${local.vpc_name} VPC (${var.primary_region})"

  tags = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "secondary_vpc_fallback" {
  count = local.use_secondary_vpc_cidr_fallback ? 1 : 0

  region            = var.secondary_region
  security_group_id = aws_security_group.secondary.id
  cidr_ipv4         = data.aws_vpc.secondary.cidr_block
  ip_protocol       = "tcp"
  from_port         = var.port
  to_port           = var.port
  description       = "PostgreSQL TLS access from ${local.vpc_name} VPC (${var.secondary_region})"

  tags = local.common_tags
}
