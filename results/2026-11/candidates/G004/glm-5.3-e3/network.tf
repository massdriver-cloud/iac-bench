###############################################################################
# DB subnet groups over the network team's private database subnets, and
# security groups that allow PostgreSQL only from inside the local region's
# apps VPC. RDS requires database subnets in at least two AZs; the module
# fails fast with a clear message if the network team's subnets don't satisfy
# that instead of letting RDS emit an opaque error at the end of a long apply.
###############################################################################

resource "aws_db_subnet_group" "primary" {
  provider    = aws.primary
  name_prefix = "${local.name}-"
  description = "Private database subnets (tier=database) for ${local.primary_cluster_identifier} in ${var.primary_region}"

  subnet_ids = data.aws_subnets.primary.ids

  tags = {
    Name = "${local.name}-db-subnets"
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary.ids) >= 2
      error_message = "Fewer than 2 subnets tagged tier=database were found in the ${var.primary_region} apps VPC. Aurora requires database subnets in at least two availability zones."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.name}-"
  description = "Private database subnets (tier=database) for ${local.secondary_cluster_identifier} in ${var.secondary_region}"

  subnet_ids = data.aws_subnets.secondary.ids

  tags = {
    Name = "${local.name}-db-subnets"
  }

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary.ids) >= 2
      error_message = "Fewer than 2 subnets tagged tier=database were found in the ${var.secondary_region} apps VPC. Aurora requires database subnets in at least two availability zones."
    }
  }
}

resource "aws_security_group" "primary" {
  provider    = aws.primary
  name_prefix = "${local.name}-db-"
  description = "PostgreSQL (${var.port}) for ${local.name} from the ${var.primary_region} apps VPC"

  vpc_id = local.primary_vpc.id

  ingress {
    description = "PostgreSQL from the local apps VPC (EKS services)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = distinct(concat([local.primary_vpc.cidr_block], var.allowed_cidr_blocks))
  }

  # No egress, deliberately: databases accept connections, they don't originate
  # them. Removing the default allow-all egress is intentional least
  # privilege — Aurora's cross-region replication rides the AWS backbone and
  # does not traverse these security groups or the customer VPC.
  tags = {
    Name = "${local.name}-db"
  }
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${local.name}-db-"
  description = "PostgreSQL (${var.port}) for ${local.name} from the ${var.secondary_region} apps VPC"

  vpc_id = local.secondary_vpc.id

  ingress {
    description = "PostgreSQL from the local apps VPC (EKS services)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = distinct(concat([local.secondary_vpc.cidr_block], var.allowed_cidr_blocks))
  }

  tags = {
    Name = "${local.name}-db"
  }
}
