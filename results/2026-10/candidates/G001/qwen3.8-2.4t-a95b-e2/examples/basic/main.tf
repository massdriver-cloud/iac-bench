terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {}

module "orders_assets" {
  source = "../.."

  name        = "orders"
  environment = "dev"

  tags = {
    team = "checkout"
  }
}

output "bucket_name" {
  description = "Name of the bucket to put in the application's configuration."
  value       = module.orders_assets.bucket_name
}
