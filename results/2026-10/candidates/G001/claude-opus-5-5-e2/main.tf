locals {
  # bucket_prefix lets AWS append a unique 26-char suffix so names never collide
  # globally. AWS limits the prefix to 37 characters, so trim (and drop any
  # trailing hyphen left by trimming, then re-add one as a separator).
  bucket_prefix = "${trimsuffix(substr("${var.app_name}-${var.environment}-${var.purpose}", 0, 36), "-")}-"

  use_kms = var.kms_key_arn != null

  tags = merge(var.tags, {
    Application = var.app_name
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  })
}

resource "aws_s3_bucket" "this" {
  bucket_prefix = local.bucket_prefix
  force_destroy = var.force_destroy
}

# Disable ACLs entirely: the bucket owner owns every object.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# App asset buckets are never public. Serve public content via CloudFront (OAC)
# or presigned URLs instead.
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
    bucket_key_enabled = local.use_kms
  }
}

# Versioning protects against accidental overwrites/deletes; the lifecycle
# rules below bound how long old versions cost money.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

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

    expiration {
      expired_object_delete_marker = var.expire_objects_after_days == null ? true : null
      days                         = var.expire_objects_after_days
    }
  }

  # Let S3 move infrequently accessed objects to cheaper tiers automatically,
  # with no retrieval fees. Skipped when objects are short-lived anyway.
  dynamic "rule" {
    for_each = var.expire_objects_after_days == null || try(var.expire_objects_after_days > 60, false) ? [1] : []
    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072 # objects < 128 KB are never auto-tiered
      }

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.access_log_bucket == null ? 0 : 1
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket
  target_prefix = "s3/${aws_s3_bucket.this.id}/"
}

# Enforce encryption in transit (HTTPS with TLS 1.2+).
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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
    sid       = "DenyOutdatedTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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

# Ready-made IAM policies the app team can attach to their application's role.
data "aws_iam_policy_document" "read_write" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ReadWriteObjects"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "UseBucketKmsKey"
      actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_only" {
  statement {
    sid       = "ListBucket"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid       = "ReadObjects"
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "UseBucketKmsKey"
      actions   = ["kms:Decrypt"]
      resources = [var.kms_key_arn]
    }
  }
}
