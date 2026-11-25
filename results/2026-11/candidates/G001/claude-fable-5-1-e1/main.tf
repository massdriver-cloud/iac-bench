###############################################################################
# App assets bucket
#
# Opinionated defaults:
#   * all public access blocked, ACLs disabled (bucket owner owns everything)
#   * encryption at rest always on (SSE-S3, or SSE-KMS when a key is given)
#   * only TLS 1.2+ connections accepted
#   * versioning on, old versions cleaned up automatically
#   * abandoned multipart uploads cleaned up automatically
#   * cold data drifts to Intelligent-Tiering
###############################################################################

locals {
  use_kms           = var.kms_key_arn != null
  cors_enabled      = length(var.cors_allowed_origins) > 0
  logging_enabled   = var.access_log_bucket != null
  access_log_prefix = coalesce(var.access_log_prefix, "${var.name}/")
}

resource "aws_s3_bucket" "this" {
  bucket        = var.name
  force_destroy = var.force_destroy

  tags = merge(var.tags, { Name = var.name })
}

# ---------------------------------------------------------------------------
# Access control
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable ACLs entirely; access is governed by IAM and the bucket policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid    = "DenyOutdatedTLS"
    effect = "Deny"

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Data protection
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }

    # Bucket keys cut KMS request costs dramatically; only meaningful for SSE-KMS.
    bucket_key_enabled = local.use_kms
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle housekeeping
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # One bucket-wide housekeeping rule:
  #  - abandoned multipart uploads are invisible but billed; clean them up
  #  - previous versions are kept long enough to recover from mistakes, then removed
  #  - either expire objects after N days (if asked), or just tidy up the
  #    delete markers left behind once all versions of an object are gone.
  #    (S3 rejects configs that set both on overlapping rules, hence one-or-other.)
  rule {
    id     = "housekeeping"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    dynamic "expiration" {
      for_each = var.expiration_days != null ? [1] : []
      content {
        days = var.expiration_days
      }
    }

    dynamic "expiration" {
      for_each = var.expiration_days == null ? [1] : []
      content {
        expired_object_delete_marker = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.intelligent_tiering_after_days != null ? [1] : []

    content {
      id     = "transition-to-intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = var.intelligent_tiering_after_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # Lifecycle rules on noncurrent versions require versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.this]
}

# ---------------------------------------------------------------------------
# Optional: browser access (CORS)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.cors_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "x-amz-request-id", "x-amz-version-id"]
    max_age_seconds = 3600
  }
}

# ---------------------------------------------------------------------------
# Optional: server access logging
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = local.logging_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket
  target_prefix = local.access_log_prefix
}
