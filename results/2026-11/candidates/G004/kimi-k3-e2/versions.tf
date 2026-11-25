terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.40, < 6.0.0"
    }
  }
}

# The module deploys an Aurora global database spanning two regions, so it
# configures one aliased provider per region. Credentials come from the
# environment; regions come from variables.
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
