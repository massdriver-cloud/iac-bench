###############################################################################
# Lifecycle: keep cost bounded without ever deleting live application data
# unless the app team asked for it via var.expire_after_days.
###############################################################################

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Failed / abandoned multipart uploads are invisible but billed. Clean them up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Old versions (overwritten or deleted objects) are the recovery window, not
  # an archive: remove them after the retention period, and tidy up delete
  # markers that no longer hide anything.
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  # Objects that survive a while move to Intelligent-Tiering, which lowers the
  # price of data nobody reads without retrieval fees or slower access. (S3
  # leaves objects under 128 KB where they are, so tiny files cost nothing extra.)
  dynamic "rule" {
    for_each = var.intelligent_tiering_after_days == null ? [] : [var.intelligent_tiering_after_days]

    content {
      id     = "move-to-intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = rule.value
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # Opt-in deletion of data the application no longer needs (temp files, logs).
  dynamic "rule" {
    for_each = var.expire_after_days

    content {
      id     = rule.key == "" ? "expire-everything" : "expire-${rule.key}"
      status = "Enabled"

      filter {
        prefix = rule.key == "" ? null : rule.key
      }

      expiration {
        days = rule.value
      }
    }
  }

  # Noncurrent-version rules require versioning to be enabled first.
  depends_on = [aws_s3_bucket_versioning.this]
}
