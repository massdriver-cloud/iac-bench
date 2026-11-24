resource "aws_s3_bucket" "this" {
  bucket        = var.bucket_name
  bucket_prefix = var.bucket_name == null ? local.name_prefix : null
  force_destroy = var.force_destroy

  tags = local.common_tags
}

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

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = local.effective_versioning_enabled ? "Enabled" : "Suspended"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }
  }

  dynamic "rule" {
    for_each = local.effective_versioning_enabled && local.effective_noncurrent_expiration_days != null ? [1] : []

    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days           = local.effective_noncurrent_expiration_days
        newer_noncurrent_versions = var.noncurrent_versions_to_retain
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_versioning_enabled ? [1] : []

    content {
      id     = "cleanup-expired-delete-markers"
      status = "Enabled"

      filter {}

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_intelligent_tiering_days != null ? [1] : []

    content {
      id     = "transition-intelligent-tiering"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      transition {
        days          = local.effective_intelligent_tiering_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_ia_days != null ? [1] : []

    content {
      id     = "transition-standard-ia"
      status = "Enabled"

      filter {
        object_size_greater_than = 131072
      }

      transition {
        days          = local.effective_ia_days
        storage_class = "STANDARD_IA"
      }
    }
  }

  dynamic "rule" {
    for_each = local.effective_object_expiration_days != null ? [1] : []

    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = local.effective_object_expiration_days
      }
    }
  }
}

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_allowed_origins) > 0 ? 1 : 0

  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = [
      "Authorization",
      "Content-Type",
      "Content-MD5",
      "x-amz-*",
    ]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers = [
      "ETag",
      "x-amz-request-id",
      "x-amz-id-2",
    ]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_logging" "this" {
  count = var.access_log_bucket_name != null ? 1 : 0

  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = local.effective_access_log_prefix
}

resource "aws_s3_bucket_notification" "this" {
  count = var.enable_eventbridge ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

data "aws_iam_policy_document" "bucket_policy" {
  source_policy_documents = var.additional_bucket_policy_documents

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

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipals"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.read_write_principal_arns
      }

      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipals"
      effect = "Allow"

      principals {
        type        = "AWS"
        identifiers = var.read_only_principal_arns
      }

      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]

      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid     = "AllowCloudFrontServicePrincipalReadOnly"
      effect  = "Allow"
      actions = ["s3:GetObject"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      resources = ["${aws_s3_bucket.this.arn}/*"]

      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_ownership_controls.this,
    aws_s3_bucket_public_access_block.this,
  ]
}

data "aws_iam_policy_document" "app_read_write" {
  statement {
    sid    = "BucketListAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectReadWriteAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []

    content {
      sid    = "KmsAccessForBucketObjects"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "app_read_only" {
  statement {
    sid    = "BucketListAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []

    content {
      sid    = "KmsDecryptForBucketObjects"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}
