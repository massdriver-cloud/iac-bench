# -----------------------------------------------------------------------------
# Where we are deploying
# -----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # A predictable, globally-unique bucket name that nobody has to invent:
  #   <name>-<environment>-<account-id>-<region>
  # Input validation keeps this within S3's 63-character limit.
  bucket_name = "${var.name}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(
    {
      Application = var.name
      Environment = var.environment
      ManagedBy   = "opentofu"
      Module      = "standard-s3-bucket"
    },
    var.tags,
  )
}

# -----------------------------------------------------------------------------
# The bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = local.tags
}

# ACLs are a legacy footgun. This module only ever grants access through IAM
# and bucket policies, so ACLs are disabled outright.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Nothing inside an application-asset bucket should ever be public. There is
# deliberately no switch for this; serve content through signed URLs or a CDN.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Everything is encrypted at rest with SSE-S3: strong default encryption with
# no keys for application teams to manage.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning is the undo button for accidental overwrites and deletes. When
# disabled the bucket is set to "Suspended" rather than being recreated.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Housekeeping, in a single rule (S3 rejects lifecycle rules whose scopes
# overlap, so everything lives in one rule):
#  - abandoned multipart uploads are invisible billing leaks: abort after 7 days
#  - superseded object versions are kept for 30 days as a safety net, then pruned
#  - optionally, current objects age out after object_expiration_days
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "standard-housekeeping"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    dynamic "noncurrent_version_expiration" {
      for_each = var.versioning_enabled ? [30] : []

      content {
        noncurrent_days = noncurrent_version_expiration.value
      }
    }

    dynamic "expiration" {
      for_each = var.object_expiration_days == null ? [] : [var.object_expiration_days]

      content {
        days = expiration.value
      }
    }
  }
}

# Optional: serve assets to / accept uploads from a web application's origins.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Optional: server access logs into an existing log bucket.
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket
  target_prefix = "${aws_s3_bucket.this.id}/"
}
