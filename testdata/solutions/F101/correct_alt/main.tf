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

resource "aws_s3_bucket_policy" "app_assets" {
  bucket = aws_s3_bucket.app_assets.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowAccountRead"
        Effect = "Allow"
        Principal = {
          AWS = data.aws_caller_identity.current.account_id
        }
        Action = ["s3:GetObject"]
        Resource = [
          "arn:aws:s3:::${aws_s3_bucket.app_assets.bucket}",
          "arn:aws:s3:::${aws_s3_bucket.app_assets.bucket}/*",
        ]
      }
    ]
  })
}
