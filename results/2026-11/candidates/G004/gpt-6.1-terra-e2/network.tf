data "aws_vpc" "primary" {
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}
data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
}
data "aws_subnets" "primary" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
data "aws_subnets" "secondary" {
  provider = aws.secondary
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }
  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}
resource "aws_db_subnet_group" "primary" {
  name       = "${local.id}-primary"
  subnet_ids = data.aws_subnets.primary.ids
  tags       = local.tags
  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.primary.ids) >= 2
      error_message = "The primary VPC must have database-tagged subnets in at least two AZs."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${local.id}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  tags       = local.tags
  lifecycle {
    precondition {
      condition     = length(data.aws_subnets.secondary.ids) >= 2
      error_message = "The secondary VPC must have database-tagged subnets in at least two AZs."
    }
  }
}
resource "aws_security_group" "primary" {
  name        = "${local.id}-database"
  description = "Private PostgreSQL access for ${local.id}"
  vpc_id      = data.aws_vpc.primary.id
  tags        = local.tags
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.id}-database"
  description = "Private PostgreSQL access for ${local.id}"
  vpc_id      = data.aws_vpc.secondary.id
  tags        = local.tags
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS workload"
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  description                  = "PostgreSQL from EKS workload"
}
