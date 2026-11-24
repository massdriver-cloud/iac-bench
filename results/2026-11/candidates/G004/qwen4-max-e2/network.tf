###############################################################################
# Private database networking in each region.
# - DB subnet groups built from the network team's tier=database subnets.
# - Security groups allow 5432 only from inside the environment VPC
#   (EKS pods/nodes) plus any explicitly listed CIDRs. No public access.
###############################################################################

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = "${local.name}-aurora"
  description = "Private database subnets for ${local.name} in ${var.primary_region}"
  subnet_ids  = data.aws_subnets.database_primary.ids

  tags = {
    Name = "${local.name}-aurora"
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_primary.ids) >= 2
      error_message = "Need at least 2 subnets tagged tier=database in VPC apps-${var.environment} in ${var.primary_region} (ask the network team)."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-aurora"
  description = "Private database subnets for ${local.name} in ${var.secondary_region}"
  subnet_ids  = data.aws_subnets.database_secondary.ids

  tags = {
    Name = "${local.name}-aurora"
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_secondary.ids) >= 2
      error_message = "Need at least 2 subnets tagged tier=database in VPC apps-${var.environment} in ${var.secondary_region} (ask the network team)."
    }
  }
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name_prefix = "${local.name}-aurora-"
  description = "PostgreSQL access to ${local.name} from within the apps-${var.environment} VPC"
  vpc_id      = data.aws_vpc.primary.id

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = local.port
    to_port     = local.port
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.primary.cidr_block], var.allowed_cidr_blocks)
  }

  egress {
    description = "Responses within the environment VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  tags = {
    Name = "${local.name}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name_prefix = "${local.name}-aurora-"
  description = "PostgreSQL access to ${local.name} from within the apps-${var.environment} VPC"
  vpc_id      = data.aws_vpc.secondary.id

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = local.port
    to_port     = local.port
    protocol    = "tcp"
    cidr_blocks = concat([data.aws_vpc.secondary.cidr_block], var.allowed_cidr_blocks)
  }

  egress {
    description = "Responses within the environment VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }

  tags = {
    Name = "${local.name}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}
