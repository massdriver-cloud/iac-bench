terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

# Region and credentials come from the environment (AWS_REGION / AWS_PROFILE etc.)
# unless overridden with var.region.
provider "aws" {
  region = var.region

  default_tags {
    tags = local.tags
  }
}
