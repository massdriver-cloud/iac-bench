# S3 Bucket Resource
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = merge(
    {
      "ManagedBy" = "OpenTofu"
    },
    var.tags
  )
}

# Bucket Public Access Block Settings
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_acls
  block_public_policy     = var.block_public_policy
  ignore_public_acls      = var.ignore_public_acls
  restrict_public_buckets = var.restrict_public_buckets
}

# Ownership Controls
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# Server-Side Encryption Configuration
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : var.sse_algorithm
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = (var.kms_key_arn != null || var.sse_algorithm == "aws:kms") ? var.bucket_key_enabled : null
  }
}

# Bucket Versioning Configuration
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status     = var.versioning_enabled ? "Enabled" : "Suspended"
    mfa_delete = var.versioning_mfa_delete
  }
}

# Server Access Logging (Optional)
resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_target_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}

# CORS Configuration (Optional)
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

# Bucket Policy Data Source (TLS enforcement + optional custom statements)
data "aws_iam_policy_document" "this" {
  count = (var.enforce_tls || var.custom_policy_json != null) ? 1 : 0

  dynamic "statement" {
    for_each = var.enforce_tls ? [1] : []
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

  override_policy_documents = var.custom_policy_json != null ? [var.custom_policy_json] : []
}

# Bucket Policy Attachment
resource "aws_s3_bucket_policy" "this" {
  count  = (var.enforce_tls || var.custom_policy_json != null) ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this[0].json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
