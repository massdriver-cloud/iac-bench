################################################################################
# Lifecycle Configuration
#
# Prevents storage runaway costs:
# - Aborts abandoned multipart uploads (large files/videos/user uploads)
# - Archives and cleans up previous (noncurrent) object versions
# - Optionally transitions or expires current objects (logs, temp files)
################################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.enable_lifecycle_rules ? 1 : 0
  bucket = aws_s3_bucket.this.id

  # Rule 1: Always abort incomplete multipart uploads
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  # Rule 2: Clean up noncurrent versions (when versioning is enabled and retention is specified)
  dynamic "rule" {
    for_each = (var.versioning_enabled && var.noncurrent_version_expiration_days != null) ? [1] : []
    content {
      id     = "cleanup-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }

      dynamic "noncurrent_version_transition" {
        for_each = var.noncurrent_version_transition_days != null ? [1] : []
        content {
          noncurrent_days = var.noncurrent_version_transition_days
          storage_class   = "STANDARD_IA"
        }
      }

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # Rule 3: Transitions and expiration for current objects (if configured)
  dynamic "rule" {
    for_each = (
      var.transition_to_intelligent_tiering_days != null ||
      var.transition_to_ia_days != null ||
      var.transition_to_glacier_days != null ||
      var.expiration_days != null
    ) ? [1] : []

    content {
      id     = "current-objects-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = var.transition_to_intelligent_tiering_days != null ? [1] : []
        content {
          days          = var.transition_to_intelligent_tiering_days
          storage_class = "INTELLIGENT_TIERING"
        }
      }

      dynamic "transition" {
        for_each = var.transition_to_ia_days != null ? [1] : []
        content {
          days          = var.transition_to_ia_days
          storage_class = "STANDARD_IA"
        }
      }

      dynamic "transition" {
        for_each = var.transition_to_glacier_days != null ? [1] : []
        content {
          days          = var.transition_to_glacier_days
          storage_class = "GLACIER"
        }
      }

      dynamic "expiration" {
        for_each = var.expiration_days != null ? [1] : []
        content {
          days = var.expiration_days
        }
      }
    }
  }
}
