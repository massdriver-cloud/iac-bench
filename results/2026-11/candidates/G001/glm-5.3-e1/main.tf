###############################################################################
#
# The standard application asset bucket.
#
# Every bucket this module creates comes out with, whether anyone asked or not:
#
#   * a predictable, collision-free name: <name>-<account-id>-<region>
#   * all four S3 public-access blocks on -- the bucket is private, period
#   * ACLs disabled (bucket-owner-enforced ownership); access is IAM only
#   * encryption at rest (SSE-S3 by default, SSE-KMS when kms_key_arn is set)
#   * a bucket policy that refuses every request that is not sent over HTTPS
#   * object versioning, so overwrites and deletes are recoverable
#   * a lifecycle policy that aborts broken multipart uploads and expires old
#     object versions, so the safety net does not turn into a storage bill
#
###############################################################################

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  bucket_name = "${var.name}-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.region}"

  tags = merge(
    {
      Name = local.bucket_name
    },
    var.tags,
  )
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Deleting a bucket that still holds data must never be an accident.
  force_destroy = var.force_destroy

  tags = local.tags

  lifecycle {
    precondition {
      condition     = length(local.bucket_name) <= 63
      error_message = "The generated bucket name \"${local.bucket_name}\" exceeds the 63 characters S3 allows; please choose a shorter name."
    }
  }
}

# -----------------------------------------------------------------------------
# Access: the bucket is private.
# -----------------------------------------------------------------------------

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
    # Modern buckets do not use ACLs at all; access is governed by IAM and
    # bucket policy only, and the bucket owner always owns every object.
    object_ownership = "BucketOwnerEnforced"
  }
}

data "aws_iam_policy_document" "this" {
  # Refuse anything that is not sent over HTTPS. S3 itself would happily serve
  # plain HTTP; this policy makes it impossible.
  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    actions = ["s3:*"]

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.this.json
}

# -----------------------------------------------------------------------------
# Encryption at rest.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # Bucket keys cut KMS request costs roughly in half for SSE-KMS; the flag
    # is meaningless (and rejected) for SSE-S3, so it is only set for KMS.
    bucket_key_enabled = var.kms_key_arn == null ? null : true
  }
}

# -----------------------------------------------------------------------------
# Versioning: the undo button.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# -----------------------------------------------------------------------------
# Lifecycle: keep the safety nets from becoming the bill.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Large objects are uploaded in parts. When a client dies halfway through,
  # the already-uploaded parts linger invisibly and cost money until someone
  # cleans them up -- so the module always cleans them up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Versioning without a retention window keeps every old version forever.
  dynamic "rule" {
    for_each = var.versioning_enabled ? [1] : []

    content {
      id     = "expire-old-object-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  dynamic "rule" {
    for_each = var.infrequent_access_transition_days == null ? [] : [var.infrequent_access_transition_days]

    content {
      id     = "transition-to-infrequent-access"
      status = "Enabled"

      filter {}

      transition {
        days          = rule.value
        storage_class = "STANDARD_IA"
      }
    }
  }

  dynamic "rule" {
    for_each = var.expiration_days == null ? [] : [var.expiration_days]

    content {
      id     = "expire-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = rule.value
      }
    }
  }

  lifecycle {
    precondition {
      condition     = var.expiration_days == null || var.infrequent_access_transition_days == null || var.infrequent_access_transition_days < var.expiration_days
      error_message = "infrequent_access_transition_days must be smaller than expiration_days; otherwise objects are deleted before the transition could ever take effect."
    }
  }
}

# -----------------------------------------------------------------------------
# CORS: only when browsers talk to the bucket directly.
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = var.cors_allowed_origins

    # Browsers need the ETag to verify a completed multipart upload, and the
    # version id to know what they just stored.
    expose_headers  = ["ETag", "x-amz-version-id"]
    max_age_seconds = 3000
  }
}

# -----------------------------------------------------------------------------
# Server access logging (opt-in: it needs a log bucket that already exists).
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logs_bucket == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logs_bucket
  target_prefix = coalesce(var.access_logs_prefix, "s3-access-logs/${aws_s3_bucket.this.id}/")
}
