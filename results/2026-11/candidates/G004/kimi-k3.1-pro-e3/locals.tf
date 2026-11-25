locals {
  primary_cluster_identifier   = "${var.name}-primary"
  secondary_cluster_identifier = "${var.name}-secondary"

  common_tags = merge(
    {
      ManagedBy = "OpenTofu"
      Service   = var.name
    },
    var.tags,
  )

  primary_subnet_ids   = var.primary_db_subnet_ids != null ? sort(var.primary_db_subnet_ids) : sort(data.aws_subnets.primary[0].ids)
  secondary_subnet_ids = var.secondary_db_subnet_ids != null ? sort(var.secondary_db_subnet_ids) : sort(data.aws_subnets.secondary[0].ids)

  # These settings are deliberately common to both clusters: Aurora replicates
  # data, not parameter-group configuration, between Regions.
  cluster_parameters = {
    "rds.force_ssl"              = "1"
    "log_connections"            = "1"
    "log_disconnections"         = "1"
    "log_lock_waits"             = "1"
    "log_min_duration_statement" = "1000"
    "log_statement"              = "ddl"
  }

  iam_database_users = distinct(var.iam_database_users)
  create_iam_policy  = length(local.iam_database_users) > 0
}

data "aws_partition" "primary" {}

data "aws_partition" "secondary" {
  provider = aws.secondary
}

data "aws_caller_identity" "primary" {}

data "aws_caller_identity" "secondary" {
  provider = aws.secondary
}

data "aws_subnets" "primary" {
  count = var.primary_db_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.primary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_subnets" "secondary" {
  provider = aws.secondary
  count    = var.secondary_db_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [var.secondary_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}
