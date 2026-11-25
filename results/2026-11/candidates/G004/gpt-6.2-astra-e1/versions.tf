terraform {
  required_version = ">= 1.11.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}
provider "aws" {
  region = var.primary_region
  default_tags { tags = local.tags }
}
provider "aws" {
  alias  = "dr"
  region = var.secondary_region
  default_tags { tags = local.tags }
}
