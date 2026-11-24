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
data "aws_subnet" "primary" {
  for_each = toset(data.aws_subnets.primary.ids)
  id       = each.value
}
data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)
  id       = each.value
}
locals {
  primary_azs   = sort(distinct([for s in data.aws_subnet.primary : s.availability_zone]))
  secondary_azs = sort(distinct([for s in data.aws_subnet.secondary : s.availability_zone]))
}
resource "aws_db_subnet_group" "primary" {
  name       = "${var.name}-primary"
  subnet_ids = data.aws_subnets.primary.ids
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2 && alltrue([for s in data.aws_subnet.primary : !s.map_public_ip_on_launch])
      error_message = "Primary database subnets must span at least two AZs and disable public IP assignment. Network owners must also ensure private routing."
    }
  }
}
resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.name}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2 && alltrue([for s in data.aws_subnet.secondary : !s.map_public_ip_on_launch])
      error_message = "Secondary database subnets must span at least two AZs and disable public IP assignment."
    }
  }
}
resource "aws_security_group" "primary" {
  name_prefix = "${var.name}-db-"
  description = "Aurora: PostgreSQL only from authorized local EKS clients; no outbound rules"
  vpc_id      = data.aws_vpc.primary.id
}
resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name_prefix = "${var.name}-db-"
  description = "Aurora: PostgreSQL only from authorized local EKS clients; no outbound rules"
  vpc_id      = data.aws_vpc.secondary.id
}
resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = var.primary_client_security_group_ids
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = var.secondary_client_security_group_ids
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
