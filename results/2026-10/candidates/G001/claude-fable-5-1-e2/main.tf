data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.id
  partition  = data.aws_partition.current.partition

  # Bucket names are global. Suffixing with account id and region makes the name unique and
  # predictable without a random component (max length: 24 + 1 + 10 + 1 + 12 + 1 + 14 = 63).
  bucket_name = "${var.application}-${var.environment}-${local.account_id}-${local.region}"
  bucket_arn  = "arn:${local.partition}:s3:::${local.bucket_name}"

  use_kms        = var.kms_key_arn != null
  expire_objects = var.expire_objects_after_days != null

  common_tags = merge(
    var.tags,
    {
      Application = var.application
      Environment = var.environment
      ManagedBy   = "opentofu"
    },
  )
}

# -----------------------------------------------------------------------------
# The bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
}

# Nothing in this bucket is ever reachable anonymously. Access goes through IAM,
# pre-signed URLs, or a CDN with an origin access identity.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs are a legacy mechanism and a common source of misconfiguration; disable them
# entirely so the bucket owner owns every object and access is governed by policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Versioning protects against accidental overwrite and deletion. Old versions are
# tidied up by the lifecycle rules below so they do not accumulate forever.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.use_kms ? var.kms_key_arn : null
    }

    # Bucket keys cut KMS request volume (and cost) dramatically; not applicable to SSE-S3.
    bucket_key_enabled = local.use_kms
  }
}

# -----------------------------------------------------------------------------
# Lifecycle - keep the bucket tidy and cheap without the app team doing anything.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Failed or abandoned multipart uploads (common with large video uploads) otherwise
  # sit invisible in the bucket and are billed indefinitely.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Object expiry and clean-up behind versioning:
  #  - old (non-current) versions are removed after the retention window;
  #  - if the team asked for it, current objects expire after N days (S3 then also
  #    removes the resulting delete markers once no versions remain);
  #  - otherwise, only orphaned delete markers are removed.
  # Both expiry behaviours live in one rule because S3 rejects overlapping rules
  # that each carry an Expiration action.
  rule {
    id     = "expire-objects-and-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      days                         = local.expire_objects ? var.expire_objects_after_days : null
      expired_object_delete_marker = local.expire_objects ? null : true
    }
  }

  dynamic "rule" {
    for_each = var.intelligent_tiering ? [1] : []

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

  depends_on = [aws_s3_bucket_versioning.this]
}

# -----------------------------------------------------------------------------
# Optional: browser access (CORS) and server access logging
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag", "x-amz-request-id", "x-amz-version-id"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket_name != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = "${local.bucket_name}/"
}
