locals {
  standard_tags = merge(
    {
      "ManagedBy" = "OpenTofu"
    },
    var.environment != null ? { "Environment" = var.environment } : {},
    var.application != null ? { "Application" = var.application } : {}
  )
  merged_tags = merge(local.standard_tags, var.tags)
}

# --- Core S3 Bucket ---

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = local.merged_tags
}

# --- Ownership Controls ---
# Disables legacy ACLs and ensures the bucket owner owns all assets uploaded,
# eliminating cross-account permission and ownership issues.

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# --- Public Access Block ---
# Strict public access blocking by default. Application assets should never be
# unintentionally exposed to the public internet.

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# --- Server-Side Encryption ---
# Default AES256 (SSE-S3) encryption at rest with no additional cost, or SSE-KMS
# when a custom KMS key is specified. S3 Bucket Key is enabled to reduce KMS API costs.

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

# --- Durability & Versioning ---
# Protects assets against accidental deletion or overwrite by buggy application code.

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# --- CORS (Cross-Origin Resource Sharing) ---
# Supports web apps uploading directly to S3 via presigned URLs or fetching media assets.

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = try(cors_rule.value.allowed_headers, ["*"])
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = try(cors_rule.value.expose_headers, ["ETag"])
      max_age_seconds = try(cors_rule.value.max_age_seconds, 3600)
    }
  }
}

# --- Server Access Logging ---
# Captures detailed records for requests that are made to an S3 bucket for auditing.

resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_target_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = coalesce(var.logging_target_prefix, "s3-access-logs/${var.bucket_name}/")
}

# --- EventBridge Notifications ---
# Integrates with Amazon EventBridge for event-driven asset processing architectures.

resource "aws_s3_bucket_notification" "this" {
  count  = var.enable_eventbridge ? 1 : 0
  bucket = aws_s3_bucket.this.id

  eventbridge = true
}

# --- Bucket Security Policy ---
# Enforces HTTPS-only transport, requires minimum TLS 1.2, and merges any custom policy statements.

data "aws_iam_policy_document" "combined_bucket_policy" {
  count = (var.enforce_tls || var.custom_bucket_policy != null) ? 1 : 0

  source_policy_documents = var.custom_bucket_policy != null ? [var.custom_bucket_policy] : []

  dynamic "statement" {
    for_each = var.enforce_tls ? [1] : []
    content {
      sid     = "EnforceTLSRequestsOnly"
      effect  = "Deny"
      actions = ["s3:*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
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

  dynamic "statement" {
    for_each = var.enforce_tls && var.min_tls_version != null ? [1] : []
    content {
      sid     = "EnforceMinimumTLSVersion"
      effect  = "Deny"
      actions = ["s3:*"]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      condition {
        test     = "NumericLessThan"
        variable = "s3:TlsVersion"
        values   = [var.min_tls_version]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = (var.enforce_tls || var.custom_bucket_policy != null) ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.combined_bucket_policy[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}
