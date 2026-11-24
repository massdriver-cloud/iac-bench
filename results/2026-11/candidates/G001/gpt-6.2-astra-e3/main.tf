terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
  }
}

variable "bucket_prefix" {
  description = "Short descriptive name, e.g. catalog-prod-assets. A unique suffix is added automatically."
  type        = string
  nullable    = false
  validation {
    condition = (
      can(regex("^[a-z][a-z0-9-]{0,34}[a-z0-9]$", var.bucket_prefix)) &&
      !startswith(var.bucket_prefix, "xn--") && !startswith(var.bucket_prefix, "sthree-") && !startswith(var.bucket_prefix, "amzn-s3-demo-")
    )
    error_message = "Use 2–36 lowercase letters, digits or hyphens, beginning with a letter and ending with a letter or digit. Do not use an S3-reserved prefix."
  }
}

variable "tags" {
  description = "Optional ownership and cost allocation tags for the bucket."
  type        = map(string)
  default     = {}
  nullable    = false
}

resource "aws_s3_bucket" "assets" {
  bucket_prefix = "${var.bucket_prefix}-"
  force_destroy = false
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "assets" {
  bucket                  = aws_s3_bucket.assets.id
  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    object_ownership = "BucketOwnerEnforced"
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

resource "aws_s3_bucket_versioning" "assets" {
  bucket = aws_s3_bucket.assets.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_policy" "secure_transport" {
  bucket = aws_s3_bucket.assets.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.assets.arn, "${aws_s3_bucket.assets.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })
  depends_on = [aws_s3_bucket_public_access_block.assets]
}

resource "aws_s3_bucket_lifecycle_configuration" "assets" {
  bucket = aws_s3_bucket.assets.id
  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

output "bucket_name" {
  description = "Actual bucket name to configure in the application."
  value       = aws_s3_bucket.assets.id
}

output "bucket_arn" {
  description = "Bucket ARN for IAM policies. Append /* or a narrower key pattern for object actions."
  value       = aws_s3_bucket.assets.arn
}

output "bucket_regional_domain_name" {
  description = "Regional S3 domain name (not a public website)."
  value       = aws_s3_bucket.assets.bucket_regional_domain_name
}
