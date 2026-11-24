terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40.0"
    }
  }
}

# Primary region (default provider).
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.tags
  }
}

# Secondary (disaster recovery) region.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.tags
  }
}
