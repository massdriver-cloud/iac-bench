provider "aws" {
  region = "us-east-1"
}

module "static_assets" {
  source = "../.."

  team        = "payments"
  purpose     = "webapp"
  environment = "prod"
}
