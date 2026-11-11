###############################################################################
# Context, naming and tags
###############################################################################

data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  # S3 bucket names are global. A short, deterministic suffix derived from the
  # account and region makes the name unique without leaking the account ID and
  # without changing between runs. Worst case length is 24+1+8+1+15+1+8 = 58,
  # leaving room for the "-logs" suffix of the companion log bucket (63 max).
  name_suffix     = substr(sha256("${local.account_id}/${local.region}"), 0, 8)
  bucket_name     = "${var.app_name}-${var.environment}-${var.purpose}-${local.name_suffix}"
  log_bucket_name = "${local.bucket_name}-logs"

  # ARNs are built from the names (rather than read back from the resources) so
  # that every policy document is fully rendered and reviewable at plan time.
  bucket_arn     = "arn:${local.partition}:s3:::${local.bucket_name}"
  log_bucket_arn = "arn:${local.partition}:s3:::${local.log_bucket_name}"

  create_kms_key    = var.kms_key_arn == null
  create_log_bucket = var.access_log_bucket_name == null

  kms_key_arn       = local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn
  log_target_bucket = local.create_log_bucket ? aws_s3_bucket.logs[0].id : var.access_log_bucket_name
  log_target_prefix = "s3-access-logs/${local.bucket_name}/"

  # Objects move to Intelligent-Tiering after this many days so rarely-read
  # assets get cheaper automatically with no retrieval fees or latency penalty.
  tiering_after_days = 30
  enable_tiering     = var.expire_objects_after_days == null ? true : var.expire_objects_after_days > local.tiering_after_days

  tags = merge(var.tags, {
    Application = var.app_name
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  })
}

###############################################################################
# Encryption key (created unless the caller brings their own)
###############################################################################

data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  # Standard delegation: the owning account administers the key and access is
  # granted through IAM policies (see iam.tf), never to "*".
  statement {
    sid       = "EnableIamPoliciesInOwningAccount"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encrypts objects in S3 bucket ${local.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = local.tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

###############################################################################
# The application bucket
###############################################################################

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = merge(local.tags, { Name = local.bucket_name })
}

# Never public. Assets are served through the application (pre-signed URLs) or a CDN.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ACLs disabled: the bucket owner owns every object and access is controlled by policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Versioning lets teams recover from accidental overwrites and deletes.
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    # Bucket keys cut KMS request costs by ~99% for busy buckets.
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
  }
}

data "aws_iam_policy_document" "bucket" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
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

  statement {
    sid     = "DenyOutdatedTls"
    effect  = "Deny"
    actions = ["s3:*"]
    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*",
    ]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "NumericLessThan"
      variable = "s3:TlsVersion"
      values   = ["1.2"]
    }
  }

  # Uploads that don't mention encryption get the bucket default (KMS). Uploads
  # that explicitly ask for something weaker or different are refused.
  statement {
    sid       = "DenyUploadsWithOtherEncryption"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${local.bucket_arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["false"]
    }

    condition {
      test     = "StringNotEquals"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["aws:kms"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # S3 rejects concurrent bucket-level configuration calls; serialise them.
  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Failed/abandoned multipart uploads are invisible but billed. Clean them up.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  # Old versions (overwritten or deleted objects) stay recoverable for a
  # bounded window, then are permanently removed so storage doesn't grow forever.
  rule {
    id     = "expire-old-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.deleted_object_recovery_days
    }

    # Without an object expiry, tidy up delete markers that no longer hide any
    # version. (With an expiry, S3 does this as part of the expiration action.)
    dynamic "expiration" {
      for_each = var.expire_objects_after_days == null ? [1] : []

      content {
        expired_object_delete_marker = true
      }
    }
  }

  dynamic "rule" {
    for_each = var.expire_objects_after_days == null ? [] : [var.expire_objects_after_days]

    content {
      id     = "expire-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = rule.value
      }
    }
  }

  # Unknown access patterns are the norm for app assets: let S3 move objects
  # between access tiers on its own. Objects under 128 KB are left alone.
  dynamic "rule" {
    for_each = local.enable_tiering ? [local.tiering_after_days] : []

    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = rule.value
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# Only created when a team needs browsers to talk to the bucket directly.
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

resource "aws_s3_bucket_logging" "this" {
  bucket = aws_s3_bucket.this.id

  target_bucket = local.log_target_bucket
  target_prefix = local.log_target_prefix

  # The log bucket must accept deliveries before logging is switched on.
  depends_on = [
    aws_s3_bucket_policy.this,
    aws_s3_bucket_policy.logs,
  ]
}
