data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  is_production = contains(["prod", "production", "preprod"], var.environment)

  generated_bucket_name = substr(
    "${var.application_name}-${var.environment}-${var.purpose}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}",
    0,
    63
  )

  bucket_name   = coalesce(var.bucket_name_override, trimsuffix(local.generated_bucket_name, "-"))
  force_destroy = var.force_destroy != null ? var.force_destroy : !local.is_production

  use_kms = var.kms_key_arn != null && var.kms_key_arn != ""

  standard_tags = merge(
    {
      Application = var.application_name
      Environment = var.environment
      Purpose     = var.purpose
      ManagedBy   = "opentofu"
    },
    var.tags
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = local.force_destroy
  tags          = local.standard_tags
}

# Enforce BucketOwnerEnforced so ACLs are disabled and the bucket owner
# automatically owns every object uploaded to the bucket.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Block all forms of public access unconditionally.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable versioning by default to protect application assets against accidental overwrites/deletes.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

# Default encryption at rest (SSE-S3 AES256 by default, or SSE-KMS with Bucket Key when a KMS key ARN is supplied).
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }
  }
}

# Baseline bucket policy enforcing TLS (HTTPS-only) in transit and optional KMS encryption enforcement.
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

      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

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

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}

# Standard lifecycle rules:
# 1. Always clean up incomplete multipart uploads and expired delete markers.
# 2. Expire old noncurrent versions so versioning does not lead to unbounded storage growth.
# 3. Optionally transition objects to Intelligent-Tiering and/or expire current objects.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "abort-incomplete-multipart-and-cleanup-markers"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    expiration {
      expired_object_delete_marker = var.object_expiration_days == null ? true : null
      days                         = var.object_expiration_days
    }
  }

  rule {
    id     = "noncurrent-version-hygiene"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = var.noncurrent_version_retention_days
      newer_noncurrent_versions = var.noncurrent_versions_to_retain > 0 ? var.noncurrent_versions_to_retain : null
    }
  }

  dynamic "rule" {
    for_each = var.enable_intelligent_tiering ? [1] : []

    content {
      id     = "intelligent-tiering-cost-optimization"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072 # Only transition objects > 128 KB per S3 Intelligent-Tiering minimum eligible size
      }

      transition {
        days          = var.intelligent_tiering_transition_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }
}

# Optional CORS configuration for browser-based uploads/downloads (e.g. presigned URLs).
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = var.cors_allowed_headers
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = var.cors_expose_headers
    max_age_seconds = var.cors_max_age_seconds
  }
}

# Optional server access logging when a central logging bucket is supplied.
resource "aws_s3_bucket_logging" "this" {
  count  = var.access_log_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = "${var.application_name}/${var.environment}/${aws_s3_bucket.this.id}/"
}

# Ready-to-attach IAM policies for the application's runtime role (read-only and read-write).
data "aws_iam_policy_document" "app_read_only" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "DecryptWithKms"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]

      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "app_read_write" {
  source_policy_documents = [data.aws_iam_policy_document.app_read_only.json]

  statement {
    sid    = "ListMultipartUploads"
    effect = "Allow"

    actions = [
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "WriteAndDeleteObjects"
    effect = "Allow"

    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "EncryptWithKms"
      effect = "Allow"

      actions = [
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]

      resources = [var.kms_key_arn]
    }
  }
}
