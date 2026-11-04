data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  # Deterministic, globally unique name: <app>-<env>-<purpose>-<account>-<region>
  # Max length: 16+1+7+1+10+1+12+1+14 = 63 (the S3 limit).
  bucket_name = "${var.application}-${var.environment}-${var.purpose}-${local.account_id}-${var.region}"

  tags = merge(var.tags, {
    Application = var.application
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  })

  use_kms = var.kms_key_arn != null
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  lifecycle {
    precondition {
      condition     = !(var.force_destroy && var.environment == "prod")
      error_message = "force_destroy cannot be enabled for prod buckets."
    }
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "Generated bucket name exceeds 63 characters; shorten application or purpose."
    }
  }
}

# Disable ACLs entirely: the bucket owner owns every object.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Never public. Share content via pre-signed URLs or a CDN with origin access control.
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
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }
    bucket_key_enabled = local.use_kms ? true : null
  }
}

# Versioning protects against accidental overwrite/delete; old versions are
# cleaned up by the lifecycle rules below so cost stays bounded.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "cleanup-incomplete-uploads"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "noncurrent-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  # Let S3 move rarely-accessed objects (large media, old uploads) to cheaper
  # tiers automatically with no retrieval fees or app changes. Objects under
  # 128 KB are never charged monitoring fees and simply stay in the frequent tier.
  rule {
    id     = "intelligent-tiering"
    status = "Enabled"
    filter {}

    transition {
      days          = 0
      storage_class = "INTELLIGENT_TIERING"
    }
  }

  dynamic "rule" {
    for_each = var.expire_objects_after_days == null ? [] : [var.expire_objects_after_days]
    content {
      id     = "expire-current-objects"
      status = "Enabled"
      filter {}

      expiration {
        days = rule.value
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Enforce encryption in transit (HTTPS, TLS 1.2+).
data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  statement {
    sid     = "DenyOutdatedTLS"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

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
# Ready-made IAM policies for the application's role(s). Attach one of these
# to your app's IAM role instead of writing S3 permissions by hand.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "read_only" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject", "s3:GetObjectVersion", "s3:GetObjectTagging"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "UseKmsKey"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ReadWriteObjects"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
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
      sid       = "UseKmsKey"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}
