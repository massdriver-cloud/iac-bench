data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

# -----------------------------------------------------------------------------
# Engine Version Resolution Across Both Regions
# -----------------------------------------------------------------------------

data "aws_rds_engine_version" "primary" {
  region  = var.primary_region
  engine  = "aurora-postgresql"
  version = var.engine_version
  latest  = true

  lifecycle {
    postcondition {
      condition     = self.supports_global_databases
      error_message = "Selected Aurora PostgreSQL version ${self.version_actual} in ${var.primary_region} does not support Aurora Global Database."
    }
  }
}

data "aws_rds_engine_version" "secondary" {
  region  = var.secondary_region
  engine  = "aurora-postgresql"
  version = data.aws_rds_engine_version.primary.version_actual

  lifecycle {
    postcondition {
      condition     = self.supports_global_databases
      error_message = "Selected Aurora PostgreSQL version ${self.version_actual} is either unavailable or does not support Aurora Global Database in ${var.secondary_region}."
    }
  }
}

# -----------------------------------------------------------------------------
# Primary Region Network Discovery (VPC 'apps-<env>', Subnets 'tier = database')
# -----------------------------------------------------------------------------

data "aws_vpc" "primary" {
  region = var.primary_region
  state  = "available"

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "primary_database" {
  region = var.primary_region

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.primary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "VPC ${local.vpc_name} (${data.aws_vpc.primary.id}) in ${var.primary_region} must contain at least 2 private subnets tagged tier=database."
    }
  }
}

data "aws_subnet" "primary_database" {
  region   = var.primary_region
  for_each = toset(data.aws_subnets.primary_database.ids)
  id       = each.value
}

# -----------------------------------------------------------------------------
# Secondary Region Network Discovery (VPC 'apps-<env>', Subnets 'tier = database')
# -----------------------------------------------------------------------------

data "aws_vpc" "secondary" {
  region = var.secondary_region
  state  = "available"

  filter {
    name   = "tag:Name"
    values = [local.vpc_name]
  }
}

data "aws_subnets" "secondary_database" {
  region = var.secondary_region

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.secondary.id]
  }

  filter {
    name   = "tag:tier"
    values = ["database"]
  }

  lifecycle {
    postcondition {
      condition     = length(self.ids) >= 2
      error_message = "VPC ${local.vpc_name} (${data.aws_vpc.secondary.id}) in ${var.secondary_region} must contain at least 2 private subnets tagged tier=database."
    }
  }
}

data "aws_subnet" "secondary_database" {
  region   = var.secondary_region
  for_each = toset(data.aws_subnets.secondary_database.ids)
  id       = each.value
}
