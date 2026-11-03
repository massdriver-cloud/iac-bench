terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region
}

locals {
  name_prefix = "${var.name}-${var.environment}-"

  tags = merge(
    var.tags,
    {
      Name        = "${var.name}-${var.environment}"
      Environment = var.environment
      ManagedBy   = "OpenTofu"
    }
  )
}

resource "aws_s3_bucket" "this" {
  bucket_prefix = local.name_prefix
  force_destroy = var.force_destroy
  tags          = local.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "this" {
  count  = var.versioning_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = (var.abort_incomplete_multipart_upload_days > 0 || (var.versioning_enabled && var.noncurrent_version_expiration_days > 0)) ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    id     = "app-asset-cleanup"
    status = "Enabled"

    filter {}

    dynamic "abort_incomplete_multipart_upload" {
      for_each = var.abort_incomplete_multipart_upload_days > 0 ? [1] : []
      content {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.versioning_enabled && var.noncurrent_version_expiration_days > 0 ? [1] : []
      content {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }
}
