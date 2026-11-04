locals {
  tags = merge(
    {
      managed_by  = "opentofu"
      application = var.application
      environment = var.environment
    },
    var.tags,
  )

  bucket_policy_enabled = (
    var.enforce_tls ||
    length(var.allowed_read_principals) > 0 ||
    length(var.allowed_write_principals) > 0
  )
}

resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags
}

# Disable object ACLs entirely. Access is granted only through the bucket policy
# and IAM policies, which is the least surprising model for app teams.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
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
      sse_algorithm     = var.encryption_algorithm
      kms_master_key_id = var.encryption_algorithm == "aws:kms" ? var.kms_key_arn : null
    }
    bucket_key_enabled = var.encryption_algorithm == "aws:kms" ? true : null
  }
}

data "aws_iam_policy_document" "bucket_policy" {
  count = local.bucket_policy_enabled ? 1 : 0

  dynamic "statement" {
    for_each = var.enforce_tls ? [1] : []

    content {
      sid    = "DenyNonTLSRequests"
      effect = "Deny"

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      actions = ["s3:*"]

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

  dynamic "statement" {
    for_each = length(var.allowed_write_principals) > 0 ? [1] : []

    content {
      sid    = "AllowWriteAccess"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.allowed_write_principals
      }

      actions = [
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_read_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadAccess"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_principals
      }

      actions = [
        "s3:ListBucket",
        "s3:GetObject",
      ]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count  = local.bucket_policy_enabled ? 1 : 0
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy[0].json
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count  = var.enable_lifecycle_rules ? 1 : 0
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {
      prefix = ""
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = var.versioning_enabled ? "Enabled" : "Disabled"

    filter {
      prefix = ""
    }

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_expiration_days
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.access_logging_target_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_logging_target_bucket
  target_prefix = var.access_logging_target_prefix != null ? var.access_logging_target_prefix : "s3/${var.application}/"
}
