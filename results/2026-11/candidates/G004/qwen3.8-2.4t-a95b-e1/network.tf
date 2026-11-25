# ---------------------------------------------------------------------------
# Regional network plumbing: DB subnet groups (from the network team's
# tier = database subnets) and a security group per region that admits only
# PostgreSQL traffic from the environment VPC.
# ---------------------------------------------------------------------------

resource "aws_db_subnet_group" "primary" {
  name        = "${local.name_env}-db"
  description = "Database subnets for ${local.name_env} in ${var.primary_region}."
  subnet_ids  = sort(tolist(data.aws_subnets.database_primary.ids))
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.dr

  name        = "${local.name_env}-db"
  description = "Database subnets for ${local.secondary_cluster_id} in ${var.secondary_region}."
  subnet_ids  = sort(tolist(data.aws_subnets.database_secondary.ids))
}

resource "aws_security_group" "primary" {
  name        = "${local.name_env}-aurora"
  description = "Aurora PostgreSQL for ${local.name_env} (${var.primary_region})."
  vpc_id      = local.primary_vpc_id

  tags = {
    Name = "${local.name_env}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.dr

  name        = "${local.name_env}-aurora"
  description = "Aurora PostgreSQL for ${local.secondary_cluster_id} (${var.secondary_region})."
  vpc_id      = local.secondary_vpc_id

  tags = {
    Name = "${local.name_env}-aurora"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Ingress: PostgreSQL from the environment VPC (where the EKS workloads
# run) plus any explicitly allowed extra CIDRs. Nothing from the internet.
resource "aws_security_group_rule" "ingress_primary" {
  security_group_id = aws_security_group.primary.id
  type              = "ingress"
  description       = "PostgreSQL from the ${local.vpc_name} VPC."
  from_port         = local.postgres_port
  to_port           = local.postgres_port
  protocol          = "tcp"
  cidr_blocks       = concat([data.aws_vpc.primary.cidr_block], var.additional_ingress_cidrs)
}

resource "aws_security_group_rule" "ingress_secondary" {
  provider = aws.dr

  security_group_id = aws_security_group.secondary.id
  type              = "ingress"
  description       = "PostgreSQL from the ${local.vpc_name} VPC."
  from_port         = local.postgres_port
  to_port           = local.postgres_port
  protocol          = "tcp"
  cidr_blocks       = concat([data.aws_vpc.secondary.cidr_block], var.additional_ingress_cidrs)
}

resource "aws_security_group_rule" "egress_primary" {
  security_group_id = aws_security_group.primary.id
  type              = "egress"
  description       = "Allow all egress."
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "egress_secondary" {
  provider = aws.dr

  security_group_id = aws_security_group.secondary.id
  type              = "egress"
  description       = "Allow all egress."
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
