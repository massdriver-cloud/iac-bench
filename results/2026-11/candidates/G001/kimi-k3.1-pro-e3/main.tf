data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

locals {
  generated_name_prefix = "${var.application_name}-${var.environment}"
  generated_name_suffix = "-${data.aws_caller_identity.current.account_id}-${data.aws_region.current.name}"

  # Keep an explicit override available for existing buckets. Generated names are
  # deterministic, globally unique within the account/Region naming model, and
  # truncated safely if AWS introduces an unusually long Region name.
  generated_bucket_name = "${substr(local.generated_name_prefix, 0, 63 - length(local.generated_name_suffix))}${local.generated_name_suffix}"
  bucket_name           = coalesce(var.bucket_name, local.generated_bucket_name)

  bucket_tags = merge(var.tags, {
    Name        = local.bucket_name
    Application = var.application_name
    Environment = var.environment
    ManagedBy   = "OpenTofu"
  })
}

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.bucket_tags
}

# Disable ACLs so bucket and IAM policies are the single access-control model.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# These four independent settings protect against current and future public
# ACLs/policies. They are deliberately not configurable by module consumers.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn == null ? "AES256" : "aws:kms"
      kms_master_key_id = var.kms_key_arn
    }

    # S3 Bucket Keys reduce KMS request costs and are only valid with SSE-KMS.
    bucket_key_enabled = var.kms_key_arn != null
  }
}

data "aws_iam_policy_document" "bucket" {
  source_policy_documents = var.additional_bucket_policy_json == null ? [] : [var.additional_bucket_policy_json]

  statement {
    sid    = "DenyInsecureTransport"
    effect = "Deny"

    actions   = ["s3:*"]
    resources = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]

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
  policy = data.aws_iam_policy_document.bucket.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Active application assets are retained unless a team explicitly chooses an
  # expiration period (useful for logs and other deliberately short-lived data).
  dynamic "rule" {
    for_each = var.object_expiration_days == null ? [] : [var.object_expiration_days]

    content {
      id     = "expire-current-object-versions"
      status = "Enabled"

      filter {}

      expiration {
        days = rule.value
      }
    }
  }

  dynamic "rule" {
    for_each = var.versioning_enabled && var.noncurrent_version_expiration_days != null ? [var.noncurrent_version_expiration_days] : []

    content {
      id     = "expire-noncurrent-object-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = rule.value
      }
    }
  }

  rule {
    id     = "clean-up-incomplete-uploads-and-delete-markers"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    expiration {
      expired_object_delete_marker = true
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_logging == null ? 0 : 1

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = coalesce(var.access_logging.target_prefix, "${local.bucket_name}/")
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) == 0 ? 0 : 1

  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules

    content {
      id              = cors_rule.value.id
      allowed_headers = cors_rule.value.allowed_headers
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}
