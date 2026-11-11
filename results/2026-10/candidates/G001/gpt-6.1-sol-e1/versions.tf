terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70, < 7.0"
    }
  }
}

# Region and credentials are supplied through the normal AWS environment/profile.
provider "aws" {}
