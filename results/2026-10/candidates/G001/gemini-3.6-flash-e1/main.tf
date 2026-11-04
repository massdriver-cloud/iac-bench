resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.kms_key_arn != null ? var.bucket_key_enabled : null
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = (var.abort_incomplete_multipart_upload_days != null || (var.versioning_enabled && var.noncurrent_version_expiration_days != null) || length(var.custom_lifecycle_rules) > 0) ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_upload_days != null ? [1] : []
    content {
      id     = "abort-incomplete-multipart-upload"
      status = "Enabled"

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }

      filter {}
    }
  }

  dynamic "rule" {
    for_each = (var.versioning_enabled && var.noncurrent_version_expiration_days != null) ? [1] : []
    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }

      filter {}
    }
  }

  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.status

      dynamic "filter" {
        for_each = rule.value.prefix != null ? [rule.value.prefix] : []
        content {
          prefix = filter.value
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [rule.value.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
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

resource "aws_s3_bucket_logging" "this" {
  count  = var.logging != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging.target_bucket
  target_prefix = var.logging.target_prefix
}

data "aws_iam_policy_document" "combined" {
  count = (var.enable_tls_only_policy || var.custom_policy_document_json != null) ? 1 : 0

  source_policy_documents = var.custom_policy_document_json != null ? [var.custom_policy_document_json] : null

  dynamic "statement" {
    for_each = var.enable_tls_only_policy ? [1] : []
    content {
      sid    = "EnforceTLSRequestsOnly"
      effect = "Deny"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions = ["s3:*"]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*"
      ]

      condition {
        test     = "Bool"
        variable = "aws:SecureTransport"
        values   = ["false"]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = (var.enable_tls_only_policy || var.custom_policy_document_json != null) ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.combined[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
