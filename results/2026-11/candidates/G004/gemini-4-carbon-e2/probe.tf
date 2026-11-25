# Environment topology probes: verify that discovered tier=database subnets in both
# regions are private (no public IP auto-assignment), span at least 2 Availability Zones,
# and intersect with Availability Zones supporting the requested Aurora instance class.

data "aws_subnet" "primary_database" {
  for_each = toset(data.aws_subnets.primary_database.ids)

  region = var.primary_region
  id     = each.value

  lifecycle {
    postcondition {
      condition     = !self.map_public_ip_on_launch
      error_message = "Database subnet ${self.id} in ${var.primary_region} has map_public_ip_on_launch enabled; production databases must reside strictly in private subnets."
    }
  }
}

data "aws_subnet" "secondary_database" {
  for_each = toset(data.aws_subnets.secondary_database.ids)

  region = var.secondary_region
  id     = each.value

  lifecycle {
    postcondition {
      condition     = !self.map_public_ip_on_launch
      error_message = "Database subnet ${self.id} in ${var.secondary_region} has map_public_ip_on_launch enabled; production databases must reside strictly in private subnets."
    }
  }
}

data "aws_rds_orderable_db_instance" "primary" {
  count = local.is_serverless ? 0 : 1

  region         = var.primary_region
  engine         = "aurora-postgresql"
  engine_version = local.engine_version
  instance_class = var.instance_class
  storage_type   = var.storage_type
}

data "aws_rds_orderable_db_instance" "secondary" {
  count = local.is_serverless ? 0 : 1

  region         = var.secondary_region
  engine         = "aurora-postgresql"
  engine_version = local.engine_version
  instance_class = var.instance_class
  storage_type   = var.storage_type
}

locals {
  primary_subnet_azs   = sort(distinct([for s in data.aws_subnet.primary_database : s.availability_zone]))
  secondary_subnet_azs = sort(distinct([for s in data.aws_subnet.secondary_database : s.availability_zone]))

  primary_eligible_azs = local.is_serverless ? local.primary_subnet_azs : sort(tolist(setintersection(
    toset(local.primary_subnet_azs),
    toset(data.aws_rds_orderable_db_instance.primary[0].availability_zones)
  )))

  secondary_eligible_azs = local.is_serverless ? local.secondary_subnet_azs : sort(tolist(setintersection(
    toset(local.secondary_subnet_azs),
    toset(data.aws_rds_orderable_db_instance.secondary[0].availability_zones)
  )))
}

check "multi_az_private_database_topology" {
  assert {
    condition     = length(local.primary_eligible_azs) >= 2
    error_message = "Primary region ${var.primary_region} VPC ${local.vpc_name} must have tier=database subnets in at least 2 Availability Zones supporting ${var.instance_class} (found: ${join(", ", local.primary_eligible_azs)})."
  }

  assert {
    condition     = length(local.secondary_eligible_azs) >= 2
    error_message = "Secondary region ${var.secondary_region} VPC ${local.vpc_name} must have tier=database subnets in at least 2 Availability Zones supporting ${var.instance_class} (found: ${join(", ", local.secondary_eligible_azs)})."
  }
}
