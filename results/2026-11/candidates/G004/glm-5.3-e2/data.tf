# Account and partition identity, used in ARNs and IAM policy documents.
data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_partition" "current" {
  provider = aws.primary
}

# Resolve the Aurora PostgreSQL engine version. By default the module uses the
# default version AWS offers for new clusters in the primary region (resolved
# at plan time, guaranteed creatable, identical across the US regions); pin
# engine_version to make upgrades a deliberate, reviewed change.
data "aws_rds_engine_version" "aurora_postgresql" {
  provider     = aws.primary
  engine       = "aurora-postgresql"
  default_only = var.engine_version == "" ? true : null
  version      = var.engine_version == "" ? null : var.engine_version
}

# ---------------------------------------------------------------------------
# Network discovery. The network team owns one VPC per environment in each
# region ("apps-staging" / "apps-prod") and pre-provisions private database
# subnets in each, tagged tier = database. The module finds the right VPC for
# the deployment's environment and collects those subnets, so platform
# engineers never have to paste subnet IDs by hand.
# ---------------------------------------------------------------------------

data "aws_vpcs" "primary" {
  provider = aws.primary
}

data "aws_vpcs" "secondary" {
  provider = aws.secondary
}

data "aws_vpc" "primary_candidates" {
  provider = aws.primary
  for_each = toset(data.aws_vpcs.primary.ids)
  id       = each.value
}

data "aws_vpc" "secondary_candidates" {
  provider = aws.secondary
  for_each = toset(data.aws_vpcs.secondary.ids)
  id       = each.value
}

data "aws_subnets" "primary_database" {
  provider = aws.primary
  count    = local.primary_discovered_vpc_id != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.primary_discovered_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary
  count    = local.secondary_discovered_vpc_id != null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [local.secondary_discovered_vpc_id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }
}

# Full details of the chosen subnets, used to validate availability-zone
# spread before anything is provisioned.
data "aws_subnet" "primary_database" {
  provider = aws.primary
  for_each = toset(local.primary_subnet_ids)
  id       = each.value
}

data "aws_subnet" "secondary_database" {
  provider = aws.secondary
  for_each = toset(local.secondary_subnet_ids)
  id       = each.value
}
