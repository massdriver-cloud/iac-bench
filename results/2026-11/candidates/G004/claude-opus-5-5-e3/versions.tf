terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.80.0, < 7.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}

# Primary (writer) region. Unaliased so global resources (IAM) land here.
provider "aws" {
  region = var.primary_region

  default_tags {
    tags = local.common_tags
  }
}

# Secondary (standby / failover) region.
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region

  default_tags {
    tags = local.common_tags
  }
}
