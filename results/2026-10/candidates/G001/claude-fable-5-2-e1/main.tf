data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # <application>-<environment>-<purpose>-<account id>-<region>
  # Deterministic, self-describing and globally unique without random suffixes:
  # the account id and region make collisions with other accounts/regions
  # impossible, and nobody outside the account can squat on the name pattern
  # without knowing the account id.
  bucket_name     = "${var.application}-${var.environment}-${var.purpose}-${local.account_id}-${local.region}"
  log_bucket_name = "${local.bucket_name}-logs"

  # Longest bucket name S3 accepts is 63 characters; we always reserve room for
  # the "-logs" suffix so naming does not depend on the logging mode.
  max_bucket_name_length = 63 - length("-logs")

  create_kms_key    = var.kms_key_arn == null
  create_log_bucket = var.access_log_bucket_name == null

  kms_key_arn            = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  access_log_bucket_name = local.create_log_bucket ? aws_s3_bucket.logs[0].id : var.access_log_bucket_name

  # Days after upload at which files move to S3 Intelligent-Tiering.
  tiering_after_days = 30
  # Tiering is pointless (and only costs transition requests) for files that
  # are deleted shortly afterwards anyway.
  enable_tiering = var.expire_objects_after_days == null ? true : var.expire_objects_after_days > 90

  tags = merge(var.tags, {
    Application = var.application
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  })
}

# -----------------------------------------------------------------------------
# The bucket
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = local.bucket_name })

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= local.max_bucket_name_length
      error_message = "The generated bucket name \"${local.bucket_name}\" is ${length(local.bucket_name)} characters long; the limit is ${local.max_bucket_name_length}. Shorten `application` or `purpose`."
    }

    precondition {
      condition     = !(var.force_destroy && var.environment == "prod")
      error_message = "force_destroy is not allowed for prod buckets. Empty the bucket deliberately before removing it."
    }
  }
}

# ACLs are disabled entirely: the bucket owner owns every object and access is
# controlled only through policies.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# The bucket can never be made public, whatever anyone does to ACLs or policies
# later. Public content is served through CloudFront
# (see var.cloudfront_distribution_arns), never straight from the bucket.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  ignore_public_acls      = true
  block_public_policy     = true
  restrict_public_buckets = true

  # S3 rejects concurrent configuration changes on a new bucket; serialise them.
  depends_on = [aws_s3_bucket_ownership_controls.this]
}

# Versioning: overwritten and deleted files stay recoverable for
# var.noncurrent_version_retention_days.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Everything is encrypted at rest with a customer-managed KMS key. Uploads need
# no special headers - this default applies automatically. The bucket key keeps
# KMS request costs negligible.
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Failed/abandoned multipart uploads are invisible in listings but billed
  # forever unless cleaned up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Keep old versions only for the recovery window, optionally expire current
  # files, and clean up leftover delete markers.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_retention_days
    }

    expiration {
      days                         = var.expire_objects_after_days
      expired_object_delete_marker = var.expire_objects_after_days == null ? true : null
    }
  }

  # App teams cannot predict access patterns; Intelligent-Tiering moves files
  # between frequent/infrequent tiers automatically with no retrieval fees and
  # no latency change. (Objects under 128 KB are left in STANDARD by S3.)
  dynamic "rule" {
    for_each = local.enable_tiering ? [1] : []

    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = local.tiering_after_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # Version-related lifecycle actions require versioning to be on first.
  depends_on = [aws_s3_bucket_versioning.this]
}

# Only created when a browser front-end needs direct (pre-signed) access.
resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_origins = var.cors_allowed_origins
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

# Every request to the bucket is recorded.
resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id

  target_bucket = local.access_log_bucket_name
  target_prefix = "${local.bucket_name}/"

  # The log bucket must accept deliveries before logging is switched on.
  depends_on = [aws_s3_bucket_policy.logs]
}
