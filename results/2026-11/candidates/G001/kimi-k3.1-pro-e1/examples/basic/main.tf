terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

module "assets" {
  source = "../.."

  bucket_name = "replace-with-a-globally-unique-bucket-name"
  application = "orders"
  environment = "production"

  tags = {
    Owner = "orders-team"
  }

  expiration_rules = [
    {
      id     = "expire-temporary-logs"
      prefix = "logs/temporary/"
      days   = 30
    }
  ]
}

output "bucket_arn" {
  value = module.assets.bucket_arn
}

output "bucket_regional_domain_name" {
  value = module.assets.bucket_regional_domain_name
}
