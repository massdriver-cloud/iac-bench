locals {
  name          = "${var.service_name}-${var.environment}"
  vpc_name      = "apps-${var.environment}"
  database_name = "svc_${replace(var.service_name, "-", "_")}"
  app_user      = "app_runtime"
  admin_user    = "dbadmin"
  port          = 5432
  tags = {
    Service     = var.service_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

data "aws_vpc" "primary" {
  tags = { Name = local.vpc_name }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary
  tags     = { Name = local.vpc_name }
  lifecycle {
    precondition {
      condition     = var.primary_region != var.secondary_region
      error_message = "Global Database requires two distinct AWS regions."
    }
  }
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
  primary_azs = sort(tolist(setintersection(
    [for subnet in data.aws_subnet.primary : subnet.availability_zone],
    data.aws_rds_orderable_db_instance.primary.availability_zones,
  )))
  secondary_azs = sort(tolist(setintersection(
    [for subnet in data.aws_subnet.secondary : subnet.availability_zone],
    data.aws_rds_orderable_db_instance.secondary.availability_zones,
  )))
}

resource "aws_db_subnet_group" "primary" {
  name       = local.name
  subnet_ids = data.aws_subnets.primary.ids
  lifecycle {
    precondition {
      condition     = length(local.primary_azs) >= 2 && alltrue([for subnet in data.aws_subnet.primary : !subnet.map_public_ip_on_launch])
      error_message = "The primary VPC needs database-tier subnets with automatic public IP assignment disabled across at least two AZs supporting the selected instance class and version."
    }
  }
}

resource "aws_db_subnet_group" "secondary" {
  provider   = aws.secondary
  name       = local.name
  subnet_ids = data.aws_subnets.secondary.ids
  lifecycle {
    precondition {
      condition     = length(local.secondary_azs) >= 2 && alltrue([for subnet in data.aws_subnet.secondary : !subnet.map_public_ip_on_launch])
      error_message = "The recovery VPC needs database-tier subnets with automatic public IP assignment disabled across at least two AZs supporting the selected instance class and version."
    }
  }
}

data "aws_security_group" "primary_client" {
  id     = var.primary_client_security_group_id
  vpc_id = data.aws_vpc.primary.id
}

data "aws_security_group" "secondary_client" {
  provider = aws.secondary
  id       = var.secondary_client_security_group_id
  vpc_id   = data.aws_vpc.secondary.id
}

resource "aws_security_group" "primary" {
  name        = "${local.name}-database"
  description = "Private Aurora access from the service workload"
  vpc_id      = data.aws_vpc.primary.id
}

resource "aws_security_group" "secondary" {
  provider    = aws.secondary
  name        = "${local.name}-database"
  description = "Private Aurora access from the service workload"
  vpc_id      = data.aws_vpc.secondary.id
}

resource "aws_vpc_security_group_ingress_rule" "primary" {
  security_group_id            = aws_security_group.primary.id
  referenced_security_group_id = data.aws_security_group.primary_client.id
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}

resource "aws_vpc_security_group_ingress_rule" "secondary" {
  provider                     = aws.secondary
  security_group_id            = aws_security_group.secondary.id
  referenced_security_group_id = data.aws_security_group.secondary_client.id
  ip_protocol                  = "tcp"
  from_port                    = local.port
  to_port                      = local.port
}
