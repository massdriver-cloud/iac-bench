locals {
  has_abort_multipart = var.abort_incomplete_multipart_upload_days != null && var.abort_incomplete_multipart_upload_days > 0
  has_noncurrent_exp  = var.versioning_enabled && var.noncurrent_version_expiration_days != null && var.noncurrent_version_expiration_days > 0
  has_expiration      = var.expiration_days != null && var.expiration_days > 0
  has_custom_rules    = length(var.custom_lifecycle_rules) > 0

  has_any_lifecycle_rule = local.has_abort_multipart || local.has_noncurrent_exp || local.has_expiration || local.has_custom_rules
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = local.has_any_lifecycle_rule ? 1 : 0
  bucket = aws_s3_bucket.this.id

  # Abort incomplete multipart uploads rule
  dynamic "rule" {
    for_each = local.has_abort_multipart ? [1] : []
    content {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }
    }
  }

  # Expire noncurrent versions rule
  dynamic "rule" {
    for_each = local.has_noncurrent_exp ? [1] : []
    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  # Expire current objects rule
  dynamic "rule" {
    for_each = local.has_expiration ? [1] : []
    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = var.expiration_days
      }
    }
  }

  # Custom lifecycle rules
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      id     = rule.value.id
      status = rule.value.status

      filter {
        prefix = rule.value.prefix
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_incomplete_multipart_upload_days != null ? [rule.value.abort_incomplete_multipart_upload_days] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
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

      dynamic "transition" {
        for_each = rule.value.transitions
        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = rule.value.noncurrent_version_transitions
        content {
          noncurrent_days = noncurrent_version_transition.value.noncurrent_days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }
    }
  }
}
