locals {
  use_kms        = var.kms_key_arn != null
  sse_algorithm  = local.use_kms ? "aws:kms" : "AES256"
  effective_tags = merge({ ManagedBy = "OpenTofu" }, var.tags)

  access_log_target_prefix = var.access_log_target_prefix != null ? var.access_log_target_prefix : "${var.bucket_name}/"
}

# -----------------------------------------------------------------------------
# The bucket itself
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = local.effective_tags
}

# ACLs are a legacy access mechanism that makes permissions hard to reason
# about. BucketOwnerEnforced disables them entirely: access is governed only
# by IAM and bucket policies, and every object is owned by the bucket account.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Every object is encrypted at rest. SSE-S3 by default (free, zero
# management); SSE-KMS with bucket keys when the caller supplies a key ARN.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # bucket_key_enabled is only meaningful (and only valid) for aws:kms.
    bucket_key_enabled = local.use_kms ? true : null

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# S3's last line of defense against accidental public exposure. All four
# switches on, unless the caller explicitly opts into public read.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = !var.allow_public_read
  block_public_policy     = !var.allow_public_read
  ignore_public_acls      = !var.allow_public_read
  restrict_public_buckets = !var.allow_public_read
}

# -----------------------------------------------------------------------------
# Lifecycle: keep the bill and the object count under control automatically
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Noncurrent-version rules require versioning to be configured first.
  depends_on = [aws_s3_bucket_versioning.this]

  # Incomplete multipart uploads are invisible to apps but still bill.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  # Versioning is only a safe default if old versions don't pile up forever.
  dynamic "rule" {
    for_each = var.versioning_enabled ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      # Clean up delete markers that have no versions left underneath them.
      expiration {
        expired_object_delete_marker = true
      }

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }
}

# -----------------------------------------------------------------------------
# CORS: only configured when the caller lists origins (browser-based apps)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# -----------------------------------------------------------------------------
# Server access logging: off unless the caller points us at a log bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_target_bucket != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_target_bucket
  target_prefix = local.access_log_target_prefix
}

# -----------------------------------------------------------------------------
# Bucket policy: guardrails the module always enforces
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "bucket" {
  # Caller-supplied grants are merged in first. The module's own statements
  # below always apply; on a SID conflict, the module's statement wins.
  source_policy_documents = var.additional_bucket_policy_json != null ? [var.additional_bucket_policy_json] : []

  # Never allow plaintext HTTP access.
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

  # Public read, only when the caller explicitly opted in.
  dynamic "statement" {
    for_each = var.allow_public_read ? [1] : []

    content {
      sid    = "AllowPublicRead"
      effect = "Allow"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # When allow_public_read flips the public access block, the policy must be
  # applied strictly after it or AWS will reject the public statement.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
