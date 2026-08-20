provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      iacbench = "true"
      fixture  = "F101"
    }
  }
}

data "aws_caller_identity" "current" {}

resource "random_id" "app_suffix" {
  byte_length = 4
}

resource "aws_s3_bucket" "app_assets" {
  bucket        = "iacbench-app-assets-${random_id.app_suffix.hex}"
  force_destroy = true
}
