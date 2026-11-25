# --- Primary Bucket ---
resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

# --- KMS Key Creation (Optional) ---
resource "aws_kms_key" "this" {
  count                   = var.create_kms_key && var.sse_algorithm == "aws:kms" ? 1 : 0
  description             = "KMS CMK for S3 bucket ${var.bucket_name}"
  deletion_window_in_days = var.kms_key_deletion_window_in_days
  enable_key_rotation     = true

  tags = var.tags
}

resource "aws_kms_alias" "this" {
  count         = var.create_kms_key && var.sse_algorithm == "aws:kms" ? 1 : 0
  name          = "alias/s3-${var.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

locals {
  kms_key_arn = var.create_kms_key && var.sse_algorithm == "aws:kms" ? aws_kms_key.this[0].arn : var.kms_key_arn
}

# --- Public Access Block ---
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# --- Ownership Controls ---
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# --- Server-Side Encryption ---
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.sse_algorithm
      kms_master_key_id = var.sse_algorithm == "aws:kms" ? local.kms_key_arn : null
    }
    bucket_key_enabled = var.sse_algorithm == "aws:kms" ? var.bucket_key_enabled : null
  }
}

# --- Versioning ---
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# --- Lifecycle Configuration ---
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = (
    var.abort_incomplete_multipart_upload_days > 0 ||
    var.noncurrent_version_expiration_days != null ||
    length(var.noncurrent_version_transitions) > 0 ||
    var.expiration_days != null ||
    length(var.transitions) > 0 ||
    length(var.custom_lifecycle_rules) > 0
  ) ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Rule 1: Abort incomplete multipart upload
  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_upload_days > 0 ? [1] : []
    content {
      id     = "abort-incomplete-multipart-upload"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }
    }
  }

  # Rule 2: Noncurrent versions lifecycle
  dynamic "rule" {
    for_each = (var.noncurrent_version_expiration_days != null || length(var.noncurrent_version_transitions) > 0) ? [1] : []
    content {
      id     = "noncurrent-versions-lifecycle"
      status = var.versioning_enabled ? "Enabled" : "Disabled"

      filter {}

      dynamic "noncurrent_version_expiration" {
        for_each = var.noncurrent_version_expiration_days != null ? [var.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = var.noncurrent_version_transitions
        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }

  # Rule 3: Current versions lifecycle
  dynamic "rule" {
    for_each = (var.expiration_days != null || length(var.transitions) > 0) ? [1] : []
    content {
      id     = "current-versions-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "expiration" {
        for_each = var.expiration_days != null ? [var.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "transition" {
        for_each = var.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }

  # Custom lifecycle rules
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      id     = lookup(rule.value, "id", "custom-rule-${rule.key}")
      status = lookup(rule.value, "status", "Enabled")

      filter {
        prefix = lookup(rule.value, "prefix", "")
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = lookup(rule.value, "abort_incomplete_multipart_upload_days", null) != null ? [rule.value.abort_incomplete_multipart_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }

      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration_days", null) != null ? [rule.value.expiration_days] : []
        content {
          days = expiration.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_version_expiration_days", null) != null ? [rule.value.noncurrent_version_expiration_days] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transitions", [])
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transitions", [])
        content {
          noncurrent_days = noncurrent_version_transition.value.days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }
}

# --- CORS Configuration ---
resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

# --- Logging Configuration ---
resource "aws_s3_bucket_logging" "this" {
  count  = var.logging_target_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix
}

# --- EventBridge Notification ---
resource "aws_s3_bucket_notification" "this" {
  count  = var.enable_eventbridge ? 1 : 0
  bucket = aws_s3_bucket.this.id

  eventbridge = true
}

# --- Transfer Acceleration ---
resource "aws_s3_bucket_accelerate_configuration" "this" {
  count  = var.transfer_acceleration_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  status = "Enabled"
}

# --- Bucket Policy (SSL Enforcement + Custom Statements) ---
data "aws_iam_policy_document" "combined" {
  count = var.enforce_ssl || length(var.custom_policy_statements) > 0 ? 1 : 0

  dynamic "statement" {
    for_each = var.enforce_ssl ? [1] : []
    content {
      sid    = "AllowSSLRequestsOnly"
      effect = "Deny"
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      actions = [
        "s3:*"
      ]
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

  dynamic "statement" {
    for_each = var.custom_policy_statements
    content {
      sid           = lookup(statement.value, "sid", null)
      effect        = lookup(statement.value, "effect", "Allow")
      actions       = lookup(statement.value, "actions", null)
      not_actions   = lookup(statement.value, "not_actions", null)
      resources     = lookup(statement.value, "resources", null)
      not_resources = lookup(statement.value, "not_resources", null)

      dynamic "principals" {
        for_each = lookup(statement.value, "principals", [])
        content {
          type        = principals.value.type
          identifiers = principals.value.identifiers
        }
      }

      dynamic "not_principals" {
        for_each = lookup(statement.value, "not_principals", [])
        content {
          type        = not_principals.value.type
          identifiers = not_principals.value.identifiers
        }
      }

      dynamic "condition" {
        for_each = lookup(statement.value, "conditions", [])
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = var.enforce_ssl || length(var.custom_policy_statements) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.combined[0].json
}
