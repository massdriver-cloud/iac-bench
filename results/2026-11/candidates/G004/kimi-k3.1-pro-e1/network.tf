data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnets" "primary_database" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary_database" {
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

data "aws_subnet" "primary_database" {
  provider = aws.primary
  for_each = toset(data.aws_subnets.primary_database.ids)

  id = each.value
}

data "aws_subnet" "secondary_database" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary_database.ids)

  id = each.value
}

locals {
  primary_availability_zones = sort(distinct([
    for subnet in data.aws_subnet.primary_database : subnet.availability_zone
  ]))
  secondary_availability_zones = sort(distinct([
    for subnet in data.aws_subnet.secondary_database : subnet.availability_zone
  ]))
}

resource "aws_db_subnet_group" "primary" {
  provider = aws.primary

  name        = "${local.base_name}-primary"
  description = "Private database subnets for ${local.base_name} in ${var.primary_region}"
  subnet_ids  = sort(data.aws_subnets.primary_database.ids)

  lifecycle {
    precondition {
      condition     = length(local.primary_availability_zones) >= 2
      error_message = "The apps VPC in the primary region must have tier=database subnets in at least two availability zones."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider = aws.secondary

  name        = "${local.base_name}-secondary"
  description = "Private database subnets for ${local.base_name} in ${var.secondary_region}"
  subnet_ids  = sort(data.aws_subnets.secondary_database.ids)

  lifecycle {
    precondition {
      condition     = length(local.secondary_availability_zones) >= 2
      error_message = "The apps VPC in the secondary region must have tier=database subnets in at least two availability zones."
    }
  }
}

resource "aws_security_group" "primary" {
  provider = aws.primary

  name        = "${local.base_name}-aurora-primary"
  description = "Aurora PostgreSQL access for ${local.base_name} in ${var.primary_region}"
  vpc_id      = data.aws_vpc.primary.id

  tags = {
    Name = "${local.base_name}-aurora-primary"
  }
}

resource "aws_security_group" "secondary" {
  provider = aws.secondary

  name        = "${local.base_name}-aurora-secondary"
  description = "Aurora PostgreSQL access for ${local.base_name} in ${var.secondary_region}"
  vpc_id      = data.aws_vpc.secondary.id

  tags = {
    Name = "${local.base_name}-aurora-secondary"
  }
}

resource "aws_vpc_security_group_ingress_rule" "primary_application" {
  provider = aws.primary
  for_each = toset(var.application_security_group_ids.primary)

  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = each.value
  description                  = "PostgreSQL from an EKS application security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port

  tags = {
    Name = "${local.base_name}-primary-application"
  }
}

resource "aws_vpc_security_group_ingress_rule" "secondary_application" {
  provider = aws.secondary
  for_each = toset(var.application_security_group_ids.secondary)

  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = each.value
  description                  = "PostgreSQL from an EKS application security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port

  tags = {
    Name = "${local.base_name}-secondary-application"
  }
}
