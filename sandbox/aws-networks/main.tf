# Networks the G004 (Aurora global database) brief describes, in the four US
# commercial regions: per environment, one VPC named apps-<env> with private
# subnets tagged tier = database. No gateways, NAT or endpoints: nothing here
# bills. Applied once per sandbox account; models look these up by name and tag.

terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"
  default_tags {
    tags = { managed-by = "iac-bench-sandbox" }
  }
}

variable "environments" {
  description = "Environment VPCs to create in each region, with their /16 CIDR blocks."
  type        = map(string)
  default = {
    staging = "10.10.0.0/16"
    prod    = "10.20.0.0/16"
  }
}

variable "regions" {
  description = "Regions that hold the environment VPCs."
  type        = set(string)
  default     = ["us-east-1", "us-east-2", "us-west-1", "us-west-2"]
}

data "aws_availability_zones" "available" {
  for_each = var.regions
  region   = each.key
  state    = "available"
  filter {
    name   = "zone-type"
    values = ["availability-zone"]
  }
}

locals {
  vpcs = {
    for pair in setproduct(var.regions, keys(var.environments)) :
    "${pair[0]}/${pair[1]}" => { region = pair[0], env = pair[1], cidr = var.environments[pair[1]] }
  }
  # Up to three database subnets per VPC, one per availability zone.
  subnets = merge([
    for key, v in local.vpcs : {
      for i, az in slice(sort(data.aws_availability_zones.available[v.region].names), 0, min(3, length(data.aws_availability_zones.available[v.region].names))) :
      "${key}/${az}" => { vpc = key, region = v.region, env = v.env, az = az, cidr = cidrsubnet(v.cidr, 8, i) }
    }
  ]...)
}

resource "aws_vpc" "apps" {
  for_each             = local.vpcs
  region               = each.value.region
  cidr_block           = each.value.cidr
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags                 = { Name = "apps-${each.value.env}", environment = each.value.env }
}

resource "aws_subnet" "database" {
  for_each          = local.subnets
  region            = each.value.region
  vpc_id            = aws_vpc.apps[each.value.vpc].id
  availability_zone = each.value.az
  cidr_block        = each.value.cidr
  tags = {
    Name        = "apps-${each.value.env}-database-${each.value.az}"
    environment = each.value.env
    tier        = "database"
  }
}

output "regions" {
  description = "Regions holding the apps-staging and apps-prod VPCs."
  value       = sort(var.regions)
}

output "subnet_count" {
  description = "Database subnets created across all regions."
  value       = length(aws_subnet.database)
}
