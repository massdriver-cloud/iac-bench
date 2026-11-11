data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags
}

# The bucket is private, full stop: no public ACLs, no public policies, and
# ACLs are disabled outright so nobody can grant object-level access to the
# world by accident. Serve assets through your application or a CDN instead.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# Everything is encrypted at rest, no exceptions: this is the bucket-level
# default, so clients do not even have to ask for it.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.uses_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.uses_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.uses_kms ? local.kms_key_arn : null
    }
  }
}

# A dedicated KMS key, created only when SSE-KMS is requested and the caller
# does not bring their own key. Rotation is on; deletion is delayed 30 days so
# a mistaken destroy can be undone.
resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Server-side encryption key for S3 bucket ${local.bucket_name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

# Cost and retention hygiene: unfinished large uploads and old object versions
# are cleaned up automatically instead of quietly accumulating cost forever,
# and objects are stored in the access-aware Intelligent-Tiering class.
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = length(local.lifecycle_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "rule" {
    for_each = local.lifecycle_rules

    content {
      id     = rule.value.id
      status = "Enabled"
      filter {}

      dynamic "abort_incomplete_multipart_upload" {
        for_each = rule.value.abort_days > 0 ? [rule.value.abort_days] : []

        content {
          days_after_initiation = abort_incomplete_multipart_upload.value
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_expiration_days > 0 ? [rule.value.noncurrent_expiration_days] : []

        content {
          noncurrent_days = noncurrent_version_expiration.value
        }
      }

      dynamic "expiration" {
        for_each = rule.value.object_expiration_days > 0 ? [rule.value.object_expiration_days] : []

        content {
          days = expiration.value
        }
      }

      dynamic "transition" {
        for_each = rule.value.transition_to_it ? [1] : []

        content {
          days          = 0
          storage_class = "INTELLIGENT_TIERING"
        }
      }
    }
  }

  # Noncurrent-version rules only take effect once versioning is in place.
  depends_on = [aws_s3_bucket_versioning.this]
}

# Optional deeper savings for data you rarely open: objects in the
# Intelligent-Tiering class that nobody has accessed for this many days move
# to the Glacier archive tier. Opt-in, because retrieval from the archive
# tier takes up to a few hours.
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count = var.archive_objects_after_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "archive-cold-objects"
  status = "Enabled"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = var.archive_objects_after_days
  }
}

# Minimal CORS for web apps that upload/download directly with presigned
# URLs. Only created when origins are actually declared.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# Optional: ship this bucket's access logs to a central log bucket.
resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_target_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_log_target_bucket
  target_prefix = coalesce(var.access_log_target_prefix, "${local.bucket_name}/")
}
