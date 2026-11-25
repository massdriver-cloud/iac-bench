terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# This module is applied directly as a root module and manages resources in two
# regions: the region hosting the writable (primary) cluster and the region
# hosting the standby (secondary) cluster of the Aurora global database. Every
# resource is explicit about which regional provider it belongs to.

provider "aws" {
  alias  = "primary"
  region = var.primary_region

  default_tags {
    tags = local.default_tags
  }
}

provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.default_tags
  }
}
