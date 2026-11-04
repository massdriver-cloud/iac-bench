data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "bucket" {
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

locals {
  # Bucket names are global. The account ID keeps names unique across accounts
  # without asking the app team to invent a random suffix.
  # Worst case length: 20 + 7 + 12 + 12 + 3 separators = 54 (limit is 63).
  bucket_name = "${var.app_name}-${var.environment}-${var.asset_class}-${data.aws_caller_identity.current.account_id}"

  common_tags = {
    Application = var.app_name
    Environment = var.environment
    Owner       = var.owner_team
    AssetClass  = var.asset_class
    ManagedBy   = "opentofu"
  }

  # Retention and lifecycle defaults per asset class. null means "not set".
  asset_profiles = {
    "user-uploads" = {
      current_expiration_days    = null
      transition_days            = null
      transition_storage_class   = null
      noncurrent_expiration_days = 90
    }
    "media" = {
      current_expiration_days    = null
      transition_days            = 90
      transition_storage_class   = "STANDARD_IA"
      noncurrent_expiration_days = 30
    }
    "generated" = {
      current_expiration_days    = 30
      transition_days            = null
      transition_storage_class   = null
      noncurrent_expiration_days = 7
    }
    "logs" = {
      current_expiration_days    = 90
      transition_days            = null
      transition_storage_class   = null
      noncurrent_expiration_days = 7
    }
  }

  profile = local.asset_profiles[var.asset_class]
}

resource "aws_s3_bucket" "this" {
  bucket = local.bucket_name

  # Never let a routine apply or destroy delete asset data. Emptying a bucket
  # with content is a deliberate manual action.
  force_destroy = false
}

# Disable ACLs. Access is controlled by IAM and bucket policy only.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning protects against accidental overwrites and deletes. Old versions
# are expired by the lifecycle configuration below.
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
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be on before noncurrent-version rules are valid.
  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  rule {
    id     = "asset-class-retention"
    status = "Enabled"

    filter {}

    dynamic "transition" {
      for_each = local.profile.transition_days == null ? [] : [1]
      content {
        days          = local.profile.transition_days
        storage_class = local.profile.transition_storage_class
      }
    }

    dynamic "expiration" {
      for_each = local.profile.current_expiration_days == null ? [] : [1]
      content {
        days = local.profile.current_expiration_days
      }
    }

    noncurrent_version_expiration {
      noncurrent_days = local.profile.noncurrent_expiration_days
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = ["GET", "PUT", "POST", "HEAD"]
    allowed_origins = var.cors_allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # Apply the policy after public access block so it is never briefly ineffective.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
