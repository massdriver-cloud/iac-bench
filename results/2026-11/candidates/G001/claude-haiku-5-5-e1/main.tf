data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  # Lifecycle defaults per asset class. Days are in days; null means "not applied".
  class_defaults = {
    "user-uploads" = { current_expiration_days = null, ia_transition_days = null, noncurrent_expiration_days = 30 }
    "media"        = { current_expiration_days = null, ia_transition_days = 30, noncurrent_expiration_days = 30 }
    "generated"    = { current_expiration_days = 90, ia_transition_days = null, noncurrent_expiration_days = 7 }
    "logs"         = { current_expiration_days = 365, ia_transition_days = 30, noncurrent_expiration_days = 30 }
  }

  defaults = local.class_defaults[var.asset_class]

  # Explicit override wins over the class default.
  expiration_days = var.object_expiration_days != null ? var.object_expiration_days : local.defaults.current_expiration_days

  # S3 requires the expiration to come after any transition, so drop the
  # transition if it would not be strictly earlier than the expiration.
  ia_transition_days = (
    local.expiration_days != null && local.defaults.ia_transition_days != null && local.defaults.ia_transition_days >= local.expiration_days
  ) ? null : local.defaults.ia_transition_days

  # Bucket names are global. A short hash of the account, region and identity
  # keeps names unique and deterministic without storing random state.
  name_hash   = substr(sha256("${data.aws_caller_identity.current.account_id}:${data.aws_region.current.name}:${var.application_name}:${var.environment}:${var.asset_class}"), 0, 10)
  bucket_name = "${var.application_name}-${var.environment}-${var.asset_class}-${local.name_hash}"

  standard_tags = {
    application = var.application_name
    environment = var.environment
    asset-class = var.asset_class
    managed-by  = "opentofu"
  }

  tags = merge(var.tags, local.standard_tags)
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Never let a routine destroy wipe application data. Removing the bucket
  # requires emptying it first.
  force_destroy = false

  tags = local.tags
}

# Disable ACLs; access is controlled by IAM and bucket policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Not configurable: buckets created by this module are never public.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Always on, so accidental overwrites and deletes are recoverable.
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
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }

    bucket_key_enabled = var.kms_key_arn != null
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be active before noncurrent-version rules are accepted.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "asset-lifecycle"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }

    noncurrent_version_expiration {
      noncurrent_days = local.defaults.noncurrent_expiration_days
    }

    dynamic "transition" {
      for_each = local.ia_transition_days == null ? [] : [local.ia_transition_days]
      content {
        days          = transition.value
        storage_class = "STANDARD_IA"
      }
    }

    dynamic "expiration" {
      for_each = local.expiration_days == null ? [] : [local.expiration_days]
      content {
        days = expiration.value
      }
    }
  }
}

# Refuse any request that does not use TLS.
data "aws_iam_policy_document" "tls_only" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    resources = [
      aws_s3_bucket.this.arn,
      "${aws_s3_bucket.this.arn}/*",
    ]

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.tls_only.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = ["GET", "HEAD", "PUT", "POST"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}
