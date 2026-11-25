terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Credentials and the default Region come from the standard AWS environment or
# shared configuration. A calling root module may configure the provider instead.
provider "aws" {}

module "application_assets" {
  source = "../.."

  application_name = "orders-web"
  environment      = "dev"

  tags = {
    Owner = "orders-team"
  }
}

output "bucket_name" {
  value = module.application_assets.bucket_name
}

output "bucket_arn" {
  value = module.application_assets.bucket_arn
}
