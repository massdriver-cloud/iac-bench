data "aws_caller_identity" "current" {}

locals {
  # Bucket names are global. Account ID keeps them unique without teams picking names.
  # Pattern: <app>-<env>-<class>-<account>; max length 30+1+7+1+9+1+12 = 61 (<= 63).
  bucket_name = "${var.application_name}-${var.environment}-${var.asset_class}-${data.aws_caller_identity.current.account_id}"

  # Asset-class defaults, chosen by the module. Teams override only via retention_days.
  default_retention_days = {
    uploads   = null
    media     = null
    generated = 90
    logs      = 365
  }

  effective_retention_days = var.retention_days != null ? var.retention_days : local.default_retention_days[var.asset_class]

  # Noncurrent (overwritten or deleted) versions are kept briefly as a safety net.
  noncurrent_version_retention_days = {
    uploads   = 30
    media     = 30
    generated = 7
    logs      = 30
  }

  cors_methods = {
    uploads   = ["GET", "HEAD", "PUT", "POST"]
    media     = ["GET", "HEAD"]
    generated = ["GET", "HEAD"]
    logs      = []
  }

  cors_enabled = length(var.allowed_origins) > 0

  encryption_kms = var.kms_key_arn != null

  tags = merge(var.additional_tags, {
    Application = var.application_name
    Environment = var.environment
    AssetClass  = var.asset_class
    OwningTeam  = var.owning_team
    ManagedBy   = "opentofu"
  })
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy

  tags = local.tags

  lifecycle {
    precondition {
      condition     = !local.cors_enabled || contains(["uploads", "media"], var.asset_class)
      error_message = "allowed_origins may only be set for asset_class uploads or media."
    }
  }
}

# Bucket owner always owns every object; ACLs are disabled so access is only via IAM and bucket policy.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# Public access is always fully blocked. There is no input to change this.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Versioning is always on, so accidental overwrites and deletes are recoverable.
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
      sse_algorithm     = local.encryption_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.encryption_kms ? var.kms_key_arn : null
    }

    bucket_key_enabled = local.encryption_kms
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be enabled before noncurrent-version rules are valid.
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
    id     = "expire-noncurrent-versions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = local.noncurrent_version_retention_days[var.asset_class]
    }
  }

  dynamic "rule" {
    for_each = local.effective_retention_days != null ? [local.effective_retention_days] : []

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = rule.value
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.cors_enabled ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_methods = local.cors_methods[var.asset_class]
    allowed_origins = var.allowed_origins
    allowed_headers = ["*"]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

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

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket.json

  # Apply after public access block so the policy is never evaluated against a public-open bucket.
  depends_on = [aws_s3_bucket_public_access_block.this]
}
