terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

# Credentials and default region come from the ambient execution environment.
# Regional resources explicitly target var.primary_region and var.secondary_region
# using AWS Provider v6's per-resource region support.
provider "aws" {}
