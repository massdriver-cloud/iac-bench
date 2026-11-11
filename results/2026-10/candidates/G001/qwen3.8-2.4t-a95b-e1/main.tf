# Standard S3 bucket for application assets.
#
# The goal of this module is that an application team never has to think about
# S3: every setting below is a deliberate, safe default, and the only required
# inputs are the application name and the environment.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# 8 hex characters of uniqueness so the same app + environment can be
# instantiated many times (recreates, parallel sandboxes, several accounts)
# without ever colliding on the globally unique S3 namespace.
resource "random_id" "this" {
  byte_length = 4

  keepers = {
    application = var.application
    environment = var.environment
  }
}

locals {
  # Globally unique, human-attributable, and comfortably inside the 63-char
  # S3 limit: app (<=16) + env (<=7) + account (12) + region (<=14) +
  # random suffix (8) + 4 dashes.
  bucket_name = lower("${var.application}-${var.environment}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}-${random_id.this.hex}")

  tags = merge(
    {
      Application = var.application
      Environment = var.environment
      ManagedBy   = "opentofu"
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = local.tags
}

# Versioning is the module's undo button: accidental deletes and overwrites
# stay recoverable for the configured retention window.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Encryption at rest, always. S3-managed keys by default (zero setup);
# a customer-managed KMS key when compliance demands it.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null
  }
}

# No ACLs, ever. Object ownership is forced to the bucket owner and all
# access is granted through IAM / bucket policies, which are auditable and
# cannot be set wrong on a per-object basis by a stray upload.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Private by default, on all four public-access settings.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = !var.allow_public_access
  block_public_policy     = !var.allow_public_access
  ignore_public_acls      = !var.allow_public_access
  restrict_public_buckets = !var.allow_public_access
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Abandoned multipart uploads are silently burning storage otherwise.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Bound the cost of versioning: old versions stay recoverable for the
  # retention window, then are pruned automatically.
  rule {
    id     = "expire-noncurrent-versions"
    status = var.versioning_enabled ? "Enabled" : "Disabled"

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }
  }

  # Opt-in expiry for buckets whose contents are genuinely transient.
  dynamic "rule" {
    for_each = var.object_expiration_days == null ? [] : [var.object_expiration_days]

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      expiration {
        days = rule.value
      }
    }
  }
}

# CORS is off unless a team names the browser origins that may talk to S3
# directly. Most presigned-upload flows go through the backend and need none.
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST", "DELETE"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
