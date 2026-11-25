terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0, < 6.0.0"
    }
  }
}

# Primary region: the Aurora global cluster's writer lives here.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

# Secondary region: the headless secondary cluster that is promoted if the
# primary region fails.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.tags
  }
}
