terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}

# Region and credentials are taken from the environment (AWS_REGION, AWS_PROFILE, ...).
provider "aws" {}
