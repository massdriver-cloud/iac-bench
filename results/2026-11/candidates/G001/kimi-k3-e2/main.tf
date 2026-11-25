locals {
  tags = merge(
    {
      ManagedBy = "opentofu"
      Module    = "app-assets-bucket"
    },
    var.tags,
  )
}

# ---------------------------------------------------------------------------
# The bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = local.tags
}

# ---------------------------------------------------------------------------
# Guardrails — deliberately not configurable. This is the point of the module.
# ---------------------------------------------------------------------------

# ACLs are a legacy footgun: disable them so access is governed by IAM and
# bucket policy alone.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# No public access, ever. Assets are served through the app, a CDN, or
# presigned URLs — never by making the bucket public.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Every object encrypted at rest: SSE-S3 by default (free, zero key
# management), or a customer-managed KMS key when the team supplies one.
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

# Versioning: an accidental overwrite or delete is recoverable.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# TLS only: plaintext HTTP requests are denied by bucket policy. Any
# team-supplied statements (extra_bucket_policy_json) are merged in alongside
# this rule — they can open access up, but never switch the guardrail off.
data "aws_iam_policy_document" "this" {
  source_policy_documents = var.extra_bucket_policy_json == null ? null : [var.extra_bucket_policy_json]

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
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json

  # The public-access block must exist first, or AWS may reject the policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# ---------------------------------------------------------------------------
# Housekeeping lifecycle — buckets should not leak money by default
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    filter {}
  }

  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    dynamic "expiration" {
      for_each = var.expiration_days > 0 ? [var.expiration_days] : []
      content {
        days = expiration.value
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    filter {}
  }

  # Versioning state must settle before lifecycle rules can reference it.
  depends_on = [aws_s3_bucket_versioning.this]
}

# ---------------------------------------------------------------------------
# Optional extras
# ---------------------------------------------------------------------------

# CORS — only when browsers talk to the bucket directly (e.g. presigned
# uploads from a web app). Server-side-only buckets get none.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Server access logging — off unless the team has a log bucket to point at.
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_target_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_target_bucket
  target_prefix = "${var.bucket_name}/"
}
