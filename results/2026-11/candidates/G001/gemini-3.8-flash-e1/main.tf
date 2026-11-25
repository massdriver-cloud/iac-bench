################################################################################
# Standard Application Asset Bucket
#
# Production-ready, secure-by-default S3 bucket for application assets:
# user uploads, media (images/videos), generated files, and logs.
################################################################################

locals {
  default_tags = merge(
    {
      "ManagedBy"   = "OpenTofu"
      "Environment" = var.environment
    },
    var.application != null ? { "Application" = var.application } : {}
  )

  merged_tags = merge(local.default_tags, var.tags)

  # Auto-select SSE algorithm: use aws:kms if a KMS key ARN is supplied
  effective_sse_algorithm = var.kms_key_arn != null ? "aws:kms" : var.sse_algorithm
}

# S3 Bucket
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = local.merged_tags
}

# Public Access Block - Enforces that bucket and objects are never publicly exposed
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# Ownership Controls - Disables legacy ACLs so bucket owner owns all objects
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# Versioning - Protects assets from accidental deletion or overwriting
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Encryption at rest - SSE-S3 (AES256) or SSE-KMS with S3 Bucket Key enabled
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = var.bucket_key_enabled

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.effective_sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# Server Access Logging (Optional)
resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_target_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix != null ? var.logging_target_prefix : "s3-access-logs/${var.bucket_name}/"
}
