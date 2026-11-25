resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.merged_tags
}

# Always block all public access. Publicly serving assets should go through CloudFront OAC
# or short-lived presigned URLs rather than public bucket ACLs/policies.
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Disable legacy S3 ACLs so the bucket-owning account always owns every uploaded object.
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
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
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  # Versioning must be configured before lifecycle rules referencing noncurrent versions.
  depends_on = [aws_s3_bucket_versioning.this]

  # Always clean up failed/abandoned multipart uploads to avoid invisible storage charges.
  rule {
    id     = "abort-incomplete-multipart-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = local.profile.multipart_abort_days
    }
  }

  # Cost-optimize objects >= 128 KiB according to the selected usage_profile.
  rule {
    id     = "storage-class-transitions"
    status = "Enabled"

    filter {
      object_size_greater_than = local.min_tiering_object_bytes
    }

    transition {
      days          = local.profile.ia_transition_days
      storage_class = local.profile.tiering_strategy
    }

    dynamic "transition" {
      for_each = local.profile.glacier_ir_transition_days != null ? [local.profile.glacier_ir_transition_days] : []
      content {
        days          = transition.value
        storage_class = "GLACIER_IR"
      }
    }
  }

  # Expire old versions when versioning is enabled so storage costs stay bounded.
  dynamic "rule" {
    for_each = local.effective_versioning_enabled ? [1] : []
    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days           = local.effective_noncurrent_days
        newer_noncurrent_versions = local.profile.newer_noncurrent_versions
      }
    }
  }

  # Clean up orphaned delete markers left behind after noncurrent versions expire.
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

  # Optional current-object expiration (enabled by default for "logs" at 365 days).
  dynamic "rule" {
    for_each = local.effective_expiration_days != null ? [local.effective_expiration_days] : []
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
  count  = length(var.cors_allowed_origins) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = var.cors_allowed_methods
    allowed_origins = var.cors_allowed_origins
    expose_headers  = ["ETag"]
    max_age_seconds = 3600
  }
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.access_logging_bucket != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_logging_bucket
  target_prefix = "${aws_s3_bucket.this.id}/"
}

resource "aws_s3_bucket_notification" "this" {
  count       = var.enable_eventbridge ? 1 : 0
  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# Bucket policy: always deny unencrypted (non-HTTPS) transport, optionally grant CloudFront OAC.
data "aws_iam_policy_document" "bucket_policy" {
  source_policy_documents = var.additional_bucket_policy_json != null ? [var.additional_bucket_policy_json] : []

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

  # Public access block must be applied before attaching a bucket policy.
  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Ready-to-use least-privilege IAM policy documents for application roles.
data "aws_iam_policy_document" "read_only" {
  statement {
    sid = "AllowBucketReadList"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "AllowObjectRead"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []
    content {
      sid = "AllowKmsDecrypt"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "write_only" {
  statement {
    sid = "AllowMultipartList"
    actions = [
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "AllowObjectWrite"
    actions = [
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []
    content {
      sid = "AllowKmsEncrypt"
      actions = [
        "kms:GenerateDataKey*",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid = "AllowBucketList"
    actions = [
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "AllowObjectReadWrite"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectAttributes",
      "s3:GetObjectTagging",
      "s3:PutObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []
    content {
      sid = "AllowKmsReadWrite"
      actions = [
        "kms:GenerateDataKey*",
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count       = var.create_iam_policies ? 1 : 0
  name        = "${aws_s3_bucket.this.id}-read-only"
  description = "Least-privilege read-only access to S3 bucket ${aws_s3_bucket.this.id}."
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.merged_tags
}

resource "aws_iam_policy" "write_only" {
  count       = var.create_iam_policies ? 1 : 0
  name        = "${aws_s3_bucket.this.id}-write-only"
  description = "Least-privilege write-only access to S3 bucket ${aws_s3_bucket.this.id}."
  policy      = data.aws_iam_policy_document.write_only.json
  tags        = local.merged_tags
}

resource "aws_iam_policy" "read_write" {
  count       = var.create_iam_policies ? 1 : 0
  name        = "${aws_s3_bucket.this.id}-read-write"
  description = "Least-privilege read-write access to S3 bucket ${aws_s3_bucket.this.id}."
  policy      = data.aws_iam_policy_document.read_write.json
  tags        = local.merged_tags
}
