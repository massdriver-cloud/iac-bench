# --- Lifecycle Configuration ---
# Prevents runaway storage costs from abandoned multipart uploads, accumulating
# old versions, and provides automatic tiering / expiration for application assets.

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.lifecycle_rules_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id

  # Rule 1: Automatically clean up stranded multipart upload chunks from interrupted uploads
  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_upload_days != null ? [1] : []
    content {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }
    }
  }

  # Rule 2: Clean up expired delete markers left behind after version deletions
  dynamic "rule" {
    for_each = var.clean_expired_delete_markers ? [1] : []
    content {
      id     = "clean-expired-delete-markers"
      status = "Enabled"

      filter {}

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # Rule 3: Manage noncurrent versions - transition to Standard-IA and expire old versions
  dynamic "rule" {
    for_each = (var.versioning_enabled && (var.noncurrent_version_expiration_days != null || var.noncurrent_version_transition_days != null)) ? [1] : []
    content {
      id     = "manage-noncurrent-versions"
      status = "Enabled"

      filter {}

      dynamic "noncurrent_version_transition" {
        for_each = var.noncurrent_version_transition_days != null ? [1] : []
        content {
          noncurrent_days           = var.noncurrent_version_transition_days
          storage_class             = "STANDARD_IA"
          newer_noncurrent_versions = var.noncurrent_version_retain_count
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = var.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days           = var.noncurrent_version_expiration_days
          newer_noncurrent_versions = var.noncurrent_version_retain_count
        }
      }
    }
  }

  # Rule 4: Current version lifecycle (transitions to IA/Glacier or expiration for temporary/log data)
  dynamic "rule" {
    for_each = (var.current_version_transition_ia_days != null || var.current_version_transition_glacier_days != null || var.current_version_expiration_days != null) ? [1] : []
    content {
      id     = "current-version-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = var.current_version_transition_ia_days != null ? [1] : []
        content {
          days          = var.current_version_transition_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "transition" {
        for_each = var.current_version_transition_glacier_days != null ? [1] : []
        content {
          days          = var.current_version_transition_glacier_days
          storage_class = "GLACIER"
        }
      }

      dynamic "expiration" {
        for_each = var.current_version_expiration_days != null ? [1] : []
        content {
          days = var.current_version_expiration_days
        }
      }
    }
  }

  # Custom lifecycle rules supplied by the caller
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      id     = rule.value.id
      status = try(rule.value.status, "Enabled")

      dynamic "filter" {
        for_each = try(rule.value.prefix, null) != null ? [1] : []
        content {
          prefix = rule.value.prefix
        }
      }

      dynamic "expiration" {
        for_each = try(rule.value.expiration_days, null) != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = try(rule.value.abort_incomplete_multipart_upload_days, null) != null ? [1] : []
        content {
          days_after_initiation = rule.value.abort_incomplete_multipart_upload_days
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
