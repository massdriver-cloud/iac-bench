terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Region and credentials are taken from the environment
# (AWS_REGION / AWS_DEFAULT_REGION, AWS_PROFILE, AWS_ACCESS_KEY_ID, ...).
provider "aws" {
  default_tags {
    tags = {
      ManagedBy = "opentofu"
      Module    = "app-assets-bucket"
    }
  }
}
