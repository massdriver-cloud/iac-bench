terraform {
  required_version = ">= 1.9.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.20, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
provider "aws" {
  region = var.primary_region
  default_tags {
    tags = merge(var.tags, { Service = var.name, Environment = var.environment, ManagedBy = "OpenTofu" })
  }
}
provider "aws" {
  alias  = "secondary"
  region = var.secondary_region
  default_tags {
    tags = merge(var.tags, { Service = var.name, Environment = var.environment, ManagedBy = "OpenTofu" })
  }
}
