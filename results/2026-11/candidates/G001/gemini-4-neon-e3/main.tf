################################################################################
# Core S3 Bucket
################################################################################

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.common_tags

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) >= 3 && length(local.bucket_name) <= 63
      error_message = "Computed S3 bucket name '${local.bucket_name}' is ${length(local.bucket_name)} characters, which exceeds the AWS 63-character limit. Shorten app_name/purpose/environment or set bucket_name_override."
    }

    precondition {
      condition     = !(var.force_destroy && local.is_production)
      error_message = "force_destroy cannot be enabled for production environments ('prod'/'production'). Empty the bucket intentionally before destroying it."
    }

    precondition {
      condition     = !(var.encryption_type == "sse_s3" && var.kms_key_arn != null)
      error_message = "kms_key_arn cannot be set when encryption_type is 'sse_s3'. Set encryption_type = 'kms' to use a KMS key."
    }

    precondition {
      condition     = !local.cors_has_wildcard_with_writes
      error_message = "cors_allowed_origins cannot include '*' when cors_allowed_methods permits write operations (PUT, POST, DELETE). Specify explicit application origins."
    }
  }
}

################################################################################
# Security Baseline: Block All Public Access & Disable Legacy ACLs
################################################################################

# Always private. Serve public assets via CloudFront Origin Access Control (OAC)
# using var.cloudfront_distribution_arns rather than opening the bucket publicly.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# BucketOwnerEnforced disables ACLs completely so every object is owned by the
# bucket account and cannot accidentally receive public ACL grants.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

################################################################################
# Data Protection: Versioning & Server-Side Encryption
################################################################################

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = local.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.sse_algorithm
      kms_master_key_id = local.kms_key_arn
    }
  }
}

################################################################################
# Cost Hygiene & Retention: Lifecycle Management
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket                                 = aws_s3_bucket.this.id
  transition_default_minimum_object_size = "varies_by_storage_class"

  depends_on = [aws_s3_bucket_versioning.this]

  # Always clean up failed multipart uploads (common with large images/videos)
  # so orphaned parts never accumulate hidden storage bills.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = local.abort_incomplete_multipart_upload_days
    }
  }

  # Automatically optimize storage costs for unpredictable asset access patterns
  # while skipping objects < 128 KB to avoid Intelligent-Tiering monitoring fees.
  dynamic "rule" {
    for_each = local.enable_intelligent_tiering ? [1] : []

    content {
      id     = "intelligent-tiering-large-objects"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # Profile-driven tiering and/or expiration for current object versions.
  dynamic "rule" {
    for_each = length(local.effective_transitions) > 0 || local.object_expiration_days != null ? [1] : []

    content {
      id     = "current-object-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = local.effective_transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "expiration" {
        for_each = local.object_expiration_days != null ? [local.object_expiration_days] : []

        content {
          days = expiration.value
        }
      }
    }
  }

  # Bound the storage cost of version history by transitioning and expiring
  # superseded versions while retaining recent versions for rollback.
  dynamic "rule" {
    for_each = local.versioning_enabled && local.noncurrent_version_expiration_days != null ? [1] : []

    content {
      id     = "noncurrent-version-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "noncurrent_version_transition" {
        for_each = local.enable_noncurrent_ia_transition ? [local.profile.noncurrent_version_ia_transition_days] : []

        content {
          noncurrent_days = noncurrent_version_transition.value
          storage_class   = "STANDARD_IA"
        }
      }

      noncurrent_version_expiration {
        noncurrent_days           = local.noncurrent_version_expiration_days
        newer_noncurrent_versions = var.noncurrent_versions_to_retain > 0 ? var.noncurrent_versions_to_retain : null
      }
    }
  }

  # Remove orphaned delete markers once all prior versions have expired.
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

  # Optional app-defined prefix rules (e.g. short TTL for a 'tmp/' prefix).
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules

    content {
      id     = "custom-${rule.value.id}"
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
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

################################################################################
# Optional Browser Access (CORS for Presigned Uploads / Direct Asset Fetching)
################################################################################

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = var.cors_allowed_methods
    allowed_headers = var.cors_allowed_headers
    expose_headers  = var.cors_expose_headers
    max_age_seconds = var.cors_max_age_seconds
  }
}

################################################################################
# Optional Observability & Performance Features
################################################################################

resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket_name != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_bucket_name
  target_prefix = coalesce(var.access_log_prefix, "s3-access-logs/${local.bucket_name}/")

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_notification" "eventbridge" {
  count = var.enable_eventbridge ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

resource "aws_s3_bucket_accelerate_configuration" "this" {
  count = var.enable_transfer_acceleration ? 1 : 0

  bucket = aws_s3_bucket.this.id
  status = "Enabled"
}

resource "aws_s3_bucket_metric" "this" {
  count = var.enable_request_metrics ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"
}
