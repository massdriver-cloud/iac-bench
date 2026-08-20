provider "aws" {
  region = "us-east-1"
}

module "static_assets" {
  source = "../.."

  team              = "payments"
  purpose           = "webapp"
  environment       = "prod"
  enable_versioning = true
  block_public_acls = true
  enable_encryption = true
  transition_days   = 60
}
