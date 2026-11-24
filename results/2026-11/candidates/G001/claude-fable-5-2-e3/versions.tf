terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0, < 7.0"
    }
  }
}

# No provider block on purpose: the region and credentials come from the
# environment (AWS_REGION, AWS_PROFILE, ...) when this is applied as a root
# module, and from the caller's provider when it is used as a child module.
