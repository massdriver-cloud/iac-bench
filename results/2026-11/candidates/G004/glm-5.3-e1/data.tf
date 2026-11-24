data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# Resolves the engine version to use (and its parameter group family) so that
# every cluster of the global database agrees. Uses the AWS default version
# for the region unless `engine_version` is pinned.
data "aws_rds_engine_version" "selected" {
  engine       = local.engine
  version      = var.engine_version
  default_only = var.engine_version == null
}

# The network team owns one VPC per environment in each region, named
# "apps-<environment>". Look it up so callers never have to pass IDs.
data "aws_vpc" "primary" {
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

# The private database subnets, tagged tier = database by the network team.
# Skipped entirely when subnet IDs are passed in explicitly.
data "aws_subnets" "primary_database" {
  count = var.primary_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  tags = var.subnet_tags
}

data "aws_subnets" "secondary_database" {
  provider = aws.secondary
  count    = var.secondary_subnet_ids == null ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  tags = var.subnet_tags
}
