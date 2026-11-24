resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.allow_force_destroy

  tags = merge(local.common_tags, {
    Name = local.bucket_name
  })

  lifecycle {
    precondition {
      condition     = !(var.environment == "prod" && var.allow_force_destroy)
      error_message = "allow_force_destroy cannot be enabled when environment is 'prod'."
    }

    precondition {
      condition     = length(local.bucket_name) >= 3 && length(local.bucket_name) <= 63
      error_message = "Generated bucket name '${local.bucket_name}' must be between 3 and 63 characters."
    }

    precondition {
      condition     = !(var.kms_key_arn != null && var.encryption_mode != "kms")
      error_message = "kms_key_arn can only be provided when encryption_mode is 'kms'."
    }

    precondition {
      condition     = !(local.cors_enabled && local.cors_has_wildcard_origin && local.cors_has_write_methods)
      error_message = "CORS wildcard origin ('*') is not permitted when write methods (PUT, POST, DELETE) are enabled. Specify explicit origins instead."
    }

    precondition {
      condition     = !(local.versioning_enabled && local.noncurrent_version_transition_ia_days > 0 && local.noncurrent_version_transition_ia_days >= local.noncurrent_version_expiration_days)
      error_message = "noncurrent_version_transition_ia_days (${local.noncurrent_version_transition_ia_days}) must be strictly less than noncurrent_version_expiration_days (${local.noncurrent_version_expiration_days})."
    }
  }
}

# ------------------------------------------------------------------------------
# Public Access Block — Always locked down; use CloudFront OAC for public assets
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ------------------------------------------------------------------------------
# Object Ownership — Disable legacy ACLs completely (AWS best practice)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# ------------------------------------------------------------------------------
# Versioning — Protects against accidental overwrites and deletions
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = local.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# ------------------------------------------------------------------------------
# Server-Side Encryption — SSE-KMS (with Bucket Key) by default, or SSE-S3
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.expected_sse_algorithm
      kms_master_key_id = local.kms_key_arn
    }
  }
}

# ------------------------------------------------------------------------------
# Lifecycle Management — Multipart cleanup, cost tiering, version hygiene
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Prevent race conditions when enabling versioning on a new bucket.
  depends_on = [aws_s3_bucket_versioning.this]

  # 1. Always abort orphaned multipart uploads so failed large uploads don't bill forever.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  # 2. Automatic cost optimization via Intelligent-Tiering for objects >= 128 KB
  #    (objects < 128 KB stay in Standard to avoid monitoring fees; day 1 avoids
  #    provider zero-value edge cases at zero extra storage cost).
  dynamic "rule" {
    for_each = local.intelligent_tiering_enabled ? [1] : []

    content {
      id     = "intelligent-tiering-objects-over-128kb"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      transition {
        days          = 1
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # 3. Tiering for log buckets: Standard -> Standard-IA (30d) -> Glacier IR (90d).
  dynamic "rule" {
    for_each = (
      local.logs_tiering_enabled &&
      (local.object_expiration_days == 0 || local.object_expiration_days > local.logs_ia_days)
    ) ? [1] : []

    content {
      id     = "logs-storage-tiering"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      transition {
        days          = local.logs_ia_days
        storage_class = "STANDARD_IA"
      }

      dynamic "transition" {
        for_each = (local.object_expiration_days == 0 || local.object_expiration_days > local.logs_glacier_ir_days) ? [1] : []

        content {
          days          = local.logs_glacier_ir_days
          storage_class = "GLACIER_IR"
        }
      }
    }
  }

  # 4. Current object expiration (enabled for logs, ephemeral, or explicit retention).
  dynamic "rule" {
    for_each = local.object_expiration_days > 0 ? [1] : []

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = local.object_expiration_days
      }
    }
  }

  # 5. Transition noncurrent versions >= 128 KB to Standard-IA (small objects skip IA
  #    to avoid the 128 KB minimum billable size charge).
  dynamic "rule" {
    for_each = (local.versioning_enabled && local.noncurrent_version_transition_ia_days > 0) ? [1] : []

    content {
      id     = "noncurrent-version-transition-ia"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      noncurrent_version_transition {
        noncurrent_days = local.noncurrent_version_transition_ia_days
        storage_class   = "STANDARD_IA"
      }
    }
  }

  # 6. Expire all noncurrent versions so versioned buckets don't grow without bound.
  dynamic "rule" {
    for_each = local.versioning_enabled ? [1] : []

    content {
      id     = "noncurrent-version-expiration"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = local.noncurrent_version_expiration_days
      }
    }
  }

  # 7. Clean up orphaned delete markers once all noncurrent versions have expired.
  dynamic "rule" {
    for_each = local.versioning_enabled ? [1] : []

    content {
      id     = "cleanup-expired-delete-markers"
      status = "Enabled"

      filter {}

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # 8. Optional prefix-scoped custom lifecycle rules for mixed workloads.
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules

    content {
      id     = "custom-${rule.value.id}"
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []

        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days != null ? [1] : []

        content {
          noncurrent_days = rule.value.noncurrent_expiration_days
        }
      }

      dynamic "transition" {
        for_each = rule.value.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}

# ------------------------------------------------------------------------------
# CORS — Enabled only when explicit browser origins are configured
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.cors_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = var.cors_allowed_methods
    allowed_headers = var.cors_allowed_headers
    expose_headers  = var.cors_expose_headers
    max_age_seconds = var.cors_max_age_seconds
  }
}

# ------------------------------------------------------------------------------
# EventBridge Notifications — Decoupled event-driven processing
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_notification" "this" {
  count = var.enable_eventbridge ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# ------------------------------------------------------------------------------
# CloudWatch Request Metrics (opt-in due to custom metric charges)
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_metric" "this" {
  count = var.enable_request_metrics ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"
}
