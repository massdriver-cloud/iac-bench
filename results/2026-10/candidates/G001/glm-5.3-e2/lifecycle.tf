# ---------------------------------------------------------------------------
# Lifecycle: the standard hygiene rules that keep a bucket cheap, plus
# opt-in expiry and storage-class transitions for cost control.
#
# Always on (unless disabled explicitly):
#   - incomplete multipart uploads are aborted after 7 days
#   - noncurrent object versions expire after 90 days (versioning's cost)
#   - expired delete markers (deletes of already-deleted objects) are removed
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Multipart uploads that were started but never completed leave invisible
  # parts behind that cost money. Abandon them after a grace period.
  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_uploads_after_days != null ? [1] : []

    content {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_uploads_after_days
      }
    }
  }

  # Versioning keeps the previous version of every overwritten or deleted
  # object. Expire those old versions after a retention window instead of
  # paying for them forever.
  dynamic "rule" {
    for_each = var.expire_noncurrent_versions_after_days != null ? [1] : []

    content {
      id     = "expire-noncurrent-object-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.expire_noncurrent_versions_after_days
      }
    }
  }

  # A delete of an already-deleted object leaves a "delete marker" behind.
  # Once that marker no longer hides any version, it is pure noise - remove it.
  rule {
    id     = "remove-expired-delete-markers"
    status = "Enabled"

    filter {}

    expiration {
      expired_object_delete_marker = true
    }
  }

  # Optional: hard expiry of everything in the bucket, e.g. scratch or
  # log-type data that only needs to survive a fixed number of days.
  dynamic "rule" {
    for_each = var.expire_objects_after_days != null ? [1] : []

    content {
      id     = "expire-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = var.expire_objects_after_days
      }
    }
  }

  # Optional: move ageing objects to cheaper storage classes.
  dynamic "rule" {
    for_each = length(local.transitions) > 0 ? [1] : []

    content {
      id     = "transition-old-objects"
      status = "Enabled"

      filter {}

      dynamic "transition" {
        for_each = local.transitions

        content {
          days          = transition.value.days
          storage_class = transition.value.storage_class
        }
      }
    }
  }
}
