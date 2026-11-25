# ---------------------------------------------------------------------------
# Network placement: private database subnets only, no public access, and a
# security group that accepts PostgreSQL only from inside the environment VPC
# (EKS pods get VPC-routable IPs via the AWS VPC CNI). Cross-region Aurora
# global-database replication runs over AWS's private backbone and does not
# need any security-group ingress.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = local.name
  description = "Private database subnets for ${local.name} (primary)"
  subnet_ids  = data.aws_subnets.database_primary.ids
  tags        = var.tags

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_primary.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.primary_region} must have at least 2 subnets tagged tier=database in different AZs."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = local.name
  description = "Private database subnets for ${local.name} (DR)"
  subnet_ids  = data.aws_subnets.database_secondary.ids
  tags        = var.tags

  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.database_secondary.ids) >= 2
      error_message = "The ${local.vpc_name} VPC in ${var.secondary_region} must have at least 2 subnets tagged tier=database in different AZs."
    }
  }
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-db"
  description = "PostgreSQL access to ${local.name} from within ${local.vpc_name} only"
  vpc_id      = data.aws_vpc.primary.id
  tags        = var.tags

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.primary.cidr_block]
  }

  # No egress rules: security groups are stateful and the database never
  # initiates outbound connections to workloads.
  egress = []
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.name}-db"
  description = "PostgreSQL access to ${local.name} from within ${local.vpc_name} only"
  vpc_id      = data.aws_vpc.secondary.id
  tags        = var.tags

  ingress {
    description = "PostgreSQL from the environment VPC (EKS workloads)"
    from_port   = var.port
    to_port     = var.port
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.secondary.cidr_block]
  }

  egress = []
}
