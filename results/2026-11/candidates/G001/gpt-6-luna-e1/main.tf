terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_name = "assets-${var.app_name}-${var.environment}-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Application = var.app_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  }
}

resource "aws_s3_bucket" "assets" {
  bucket        = local.bucket_name
  force_destroy = false

  tags = local.common_tags
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket = aws_s3_bucket.assets.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_policy" "require_tls" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource = [
        aws_s3_bucket.assets.arn,
        "${aws_s3_bucket.assets.arn}/*"
      ]
      Condition = {
        Bool = {
          "aws:SecureTransport" = "false"
        }
      }
    }]
  })
}

output "bucket_name" {
  description = "Name of the private application assets bucket."
  value       = aws_s3_bucket.assets.bucket
}

output "bucket_arn" {
  description = "ARN of the application assets bucket."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_region" {
  description = "AWS region containing the bucket."
  value       = data.aws_region.current.region
}

output "bucket_regional_domain_name" {
  description = "Regional S3 endpoint for the bucket."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
