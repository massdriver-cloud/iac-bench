data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

###############################################################################
# Network owned by the network team: one VPC per environment in each region,
# with private database subnets tagged tier = database.
###############################################################################

data "aws_vpc" "primary" {
  provider = aws.primary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  tags = {
    Name = "apps-${var.environment}"
  }
}

data "aws_subnets" "primary" {
  provider = aws.primary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = {
    tier = "database"
  }
}

data "aws_subnet" "primary" {
  provider = aws.primary
  for_each = toset(data.aws_subnets.primary.ids)

  id = each.value
}

data "aws_subnet" "secondary" {
  provider = aws.secondary
  for_each = toset(data.aws_subnets.secondary.ids)

  id = each.value
}

###############################################################################
# Fail at plan time if the chosen engine version or instance class cannot be
# used for a global database in either region, instead of half-way through an
# apply.
###############################################################################

data "aws_rds_engine_version" "primary" {
  provider = aws.primary

  engine  = local.engine
  version = var.engine_version
}

data "aws_rds_engine_version" "secondary" {
  provider = aws.secondary

  engine  = local.engine
  version = var.engine_version
}

data "aws_rds_orderable_db_instance" "primary" {
  provider = aws.primary

  engine                     = local.engine
  engine_version             = data.aws_rds_engine_version.primary.version_actual
  preferred_instance_classes = [var.instance_class]
  supports_global_databases  = true
}

data "aws_rds_orderable_db_instance" "secondary" {
  provider = aws.secondary

  engine                     = local.engine
  engine_version             = data.aws_rds_engine_version.secondary.version_actual
  preferred_instance_classes = [var.instance_class]
  supports_global_databases  = true
}
