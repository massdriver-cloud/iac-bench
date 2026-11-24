data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # Deterministic, globally unique, DNS-compliant bucket name (max 63 chars).
  # Format: <application>-<environment>-<purpose>-<account_id>-<region>
  raw_bucket_name = "${var.application}-${var.environment}-${var.purpose}-${local.account_id}-${local.region}"
  bucket_name     = substr(local.raw_bucket_name, 0, min(63, length(local.raw_bucket_name)))

  use_kms = var.kms_key_arn != null

  default_tags = {
    Application = var.application
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  }

  merged_tags = merge(local.default_tags, var.tags)
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.merged_tags, {
    Name = local.bucket_name
  })
}

# Enforce modern S3 security best practice: disable ACLs completely so bucket owner owns all objects
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all forms of public access unconditionally
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Object Versioning
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Server-Side Encryption at Rest (SSE-S3 by default, SSE-KMS with Bucket Key when kms_key_arn is provided)
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

# Lifecycle Hygiene:
# 1. Always clean up incomplete multipart uploads (prevents silent storage leaks from failed uploads)
# 2. Manage noncurrent object versions (transition to IA, then expire)
# 3. Optionally transition current objects to Intelligent-Tiering and/or expire after N days
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  rule {
    id     = "noncurrent-version-hygiene"
    status = "Enabled"

    filter {}

    dynamic "noncurrent_version_transition" {
      for_each = var.noncurrent_version_expiration_days > var.noncurrent_version_transition_ia_days ? [1] : []
      content {
        noncurrent_days = var.noncurrent_version_transition_ia_days
        storage_class   = "STANDARD_IA"
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }

    expiration {
      expired_object_delete_marker = var.expiration_days == null
    }
  }

  dynamic "rule" {
    for_each = var.enable_intelligent_tiering ? [1] : []
    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = var.intelligent_tiering_transition_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  dynamic "rule" {
    for_each = var.expiration_days != null ? [1] : []
    content {
      id     = "object-expiration"
      status = "Enabled"

      filter {}

      expiration {
        days = var.expiration_days
      }
    }
  }
}

# Optional CORS configuration for browser uploads / frontend asset access
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# Optional server access logging
resource "aws_s3_bucket_logging" "this" {
  count  = var.access_log_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = "${var.application}/${var.environment}/${var.purpose}/"
}

# Baseline Security Bucket Policy:
# - Deny all non-TLS (HTTP) requests
# - Deny TLS versions older than TLS 1.2
# - If KMS encryption is configured, deny uploads that attempt to use a different encryption method
data "aws_iam_policy_document" "bucket_policy" {
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

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid    = "DenyIncorrectKmsKey"
      effect = "Deny"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions = ["s3:PutObject"]

      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]

      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [var.kms_key_arn]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Ready-to-use least-privilege IAM policy documents for the application's IAM role (read-only and read-write)
data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "AllowBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "AllowObjectRead"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:GetObjectVersionTagging",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid    = "AllowKmsDecrypt"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]

      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "AllowBucketList"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "AllowObjectReadWrite"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:GetObjectVersionTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid    = "AllowKmsEncryptDecrypt"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]

      resources = [var.kms_key_arn]
    }
  }
}
