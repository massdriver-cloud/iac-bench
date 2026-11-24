resource "aws_s3_bucket" "this" {
  bucket              = local.bucket_name
  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock_enabled
  tags                = local.common_tags

  lifecycle {
    precondition {
      condition     = !var.object_lock_enabled || var.enable_versioning
      error_message = "enable_versioning must be true when object_lock_enabled is true."
    }

    precondition {
      condition     = var.object_lock_retention_days == null || var.object_lock_enabled
      error_message = "object_lock_retention_days can only be set when object_lock_enabled is true."
    }

    precondition {
      condition     = var.kms_key_arn == null || var.encryption_type == "kms"
      error_message = "kms_key_arn can only be supplied when encryption_type is \"kms\"."
    }

    precondition {
      condition = (
        local.effective_intelligent_tiering ||
        local.effective_archive_after_days == null ||
        local.effective_object_expiration_days == null ||
        local.effective_archive_after_days < local.effective_object_expiration_days
      )
      error_message = "archive_after_days must be less than object_expiration_days when Intelligent-Tiering is disabled."
    }
  }
}

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
    status = var.enable_versioning ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? local.kms_key_arn : null
    }
  }
}

resource "aws_s3_bucket_object_lock_configuration" "this" {
  count = var.object_lock_enabled && var.object_lock_retention_days != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  rule {
    default_retention {
      mode = var.object_lock_mode
      days = var.object_lock_retention_days
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

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

resource "aws_s3_bucket_notification" "this" {
  count = var.enable_eventbridge ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

resource "aws_s3_bucket_metric" "this" {
  count = var.enable_request_metrics ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "EntireBucket"
}
