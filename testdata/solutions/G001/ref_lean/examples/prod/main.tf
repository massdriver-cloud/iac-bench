provider "aws" {
  region = "us-east-1"
}

module "static_assets" {
  source = "../.."

  purpose         = "webapp"
  environment     = "prod"
  transition_days = 60
}
