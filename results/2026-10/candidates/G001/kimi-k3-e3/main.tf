# Standard application asset bucket.
#
# This module is the sanctioned way for application teams to get an S3 bucket
# for the assets their app stores and works with (user uploads, images and
# video, generated files, logs). App teams pick a name and some tags; every
# other decision is owned by this module and documented in the README.

data "aws_partition" "current" {}

locals {
  use_kms = var.kms_key_arn != null
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Access safety — these are intentionally NOT exposed as variables.
# ---------------------------------------------------------------------------

# No application asset bucket should ever be public. All four public-access
# guards are pinned on, unconditionally.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are a legacy second access-control mechanism that confuses everyone.
# Disable them so IAM/bucket policies are the single way access is granted.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Every request to the bucket must use TLS.
resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.this.bucket}",
          "arn:${data.aws_partition.current.partition}:s3:::${aws_s3_bucket.this.bucket}/*",
        ]
        Condition = {
          Bool = {
            "aws:SecureTransport" = "false"
          }
        }
      }
    ]
  })

  # Ensure the public access guards exist before any bucket policy does.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Data protection
# ---------------------------------------------------------------------------

# Everything is encrypted at rest. SSE-S3 (AES256) is the default because it is
# free and needs no key management; teams with a concrete need (compliance,
# cross-account access) can bring a KMS key via kms_key_arn.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }

    # Cheap KMS requests when a KMS key is in use; irrelevant for SSE-S3.
    bucket_key_enabled = local.use_kms
  }
}

# Versioning is on by default: cheap insurance against accidental deletes and
# overwrites. The lifecycle configuration below expires old versions so cost
# stays bounded.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Half-finished multipart uploads are invisible and cost money forever
  # unless they are cleaned up. Abort them after a few days.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  # Keep old versions around as an undo window, then let them go so versioned
  # buckets don't grow without bound.
  dynamic "rule" {
    for_each = var.versioning_enabled ? [var.noncurrent_version_expiration_days] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {
        prefix = ""
      }

      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
    }
  }

  # Optional: auto-delete objects after N days. Only for disposable content
  # (logs, scratch files) — off by default.
  dynamic "rule" {
    for_each = var.object_expiration_days == null ? [] : [var.object_expiration_days]

    content {
      id     = "expire-objects"
      status = "Enabled"

      filter {
        prefix = ""
      }

      expiration {
        days = rule.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# ---------------------------------------------------------------------------
# Optional extras — off unless the team opts in
# ---------------------------------------------------------------------------

# Server access logging, for teams that need an audit trail of every request.
resource "aws_s3_bucket_logging" "this" {
  count = var.access_logging == null ? 0 : 1

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_logging.target_bucket
  target_prefix = coalesce(var.access_logging.target_prefix, "s3-access-logs/${var.name}/")
}

# CORS rules for direct browser access (e.g. uploads straight from a web app
# via presigned URLs). Empty by default: no cross-origin access.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      id              = cors_rule.value.id
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}
