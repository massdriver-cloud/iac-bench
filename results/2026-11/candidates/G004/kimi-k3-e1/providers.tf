terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.60"
    }
  }
}

# Writer region. Credentials come from the environment.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = var.tags
  }
}

# Standby region hosting the secondary cluster of the global database.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = var.tags
  }
}
