data "aws_vpc" "primary" {
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
  tags = { tier = "database" }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  filter {
    name   = "tag:Name"
    values = ["apps-${var.environment}"]
  }
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
  name       = "${var.name}-primary"
  subnet_ids = data.aws_subnets.primary.ids
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = "${var.name}-secondary"
  subnet_ids = data.aws_subnets.secondary.ids
}

resource "aws_security_group" "primary" {
  name        = "${var.name}-db"
  description = "Aurora ${var.name}: PostgreSQL from approved clients"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${var.name}-db"
  description = "Aurora ${var.name}: PostgreSQL from approved clients"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  for_each                     = toset(var.client_security_group_ids.primary)
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  for_each                     = toset(var.client_security_group_ids.secondary)
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
}
