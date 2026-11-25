locals {
  name      = "${var.service_name}-${var.environment}"
  vpc_name  = var.vpc_name_override != "" ? var.vpc_name_override : "apps-${var.environment}"
  pg_family = "aurora-postgresql${split(".", var.engine_version)[0]}"

  primary_cluster_id   = local.name
  secondary_cluster_id = "${local.name}-dr"
  global_cluster_id    = "${local.name}-global"

  common_tags = merge(
    {
      Service            = var.service_name
      Environment        = var.environment
      Component          = "aurora-postgresql"
      ManagedBy          = "opentofu"
      DataClassification = "confidential"
    },
    var.tags,
  )
}

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

# ---------------------------------------------------------------------------
# The network team owns the VPCs and database subnets. We only discover them.
# ---------------------------------------------------------------------------

data "aws_vpc" "primary" {
  provider = aws.primary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_vpc" "secondary" {
  provider = aws.secondary

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "database_primary" {
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

data "aws_subnets" "database_secondary" {
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
