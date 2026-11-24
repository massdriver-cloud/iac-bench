resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket                                 = aws_s3_bucket.this.id
  transition_default_minimum_object_size = "all_storage_classes_128K"

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = local.effective_abort_multipart_days
    }
  }

  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []

    content {
      id     = "cleanup-expired-delete-markers"
      status = "Enabled"

      filter {}

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.enable_versioning ? [1] : []

    content {
      id     = "noncurrent-version-lifecycle"
      status = "Enabled"

      filter {}

      dynamic "noncurrent_version_transition" {
        for_each = local.enable_noncurrent_transition ? [1] : []

        content {
          noncurrent_days = local.effective_noncurrent_transition_days
          storage_class   = local.effective_noncurrent_transition_storage_class
        }
      }

      noncurrent_version_expiration {
        noncurrent_days = local.effective_noncurrent_expiration_days
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_intelligent_tiering ? [1] : []

    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = 0
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  dynamic "rule" {
    for_each = !local.effective_intelligent_tiering && local.effective_archive_after_days != null ? [1] : []

    content {
      id     = "archive-current-objects"
      status = "Enabled"

      filter {}

      transition {
        days          = local.effective_archive_after_days
        storage_class = "GLACIER_IR"
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_object_expiration_days != null ? [1] : []

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = local.effective_object_expiration_days
      }
    }
  }

  dynamic "rule" {
    for_each = var.additional_lifecycle_rules

    content {
      id     = rule.value.id
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transition_days != null ? [1] : []

        content {
          days          = rule.value.transition_days
          storage_class = rule.value.transition_storage_class
        }
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
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}
