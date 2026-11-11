terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0.0, < 7.0.0"
    }
  }
}

# No provider block on purpose: region and credentials come from the
# environment (or from the calling configuration when this is used as a child
# module), so the module stays usable with count / for_each and never pins a
# team to a region it did not choose.
