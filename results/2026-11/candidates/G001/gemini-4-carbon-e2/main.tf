# -----------------------------------------------------------------------------
# Core S3 Bucket & Security Baselines
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags

  lifecycle {
    precondition {
      condition     = !(var.force_destroy && contains(["prod", "production"], var.environment))
      error_message = "force_destroy cannot be set to true when environment is \"prod\" or \"production\"."
    }

    precondition {
      condition     = !(var.create_kms_key && var.kms_key_arn != null)
      error_message = "Specify either create_kms_key = true or kms_key_arn, not both."
    }
  }
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
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# -----------------------------------------------------------------------------
# Encryption (SSE-S3 Default or Optional Customer-Managed KMS + Bucket Keys)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  count = var.create_kms_key ? 1 : 0

  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []
    content {
      sid    = "AllowCloudFrontOACDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = sort(tolist(var.cloudfront_distribution_arns))
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowReadOnlyPrincipalsViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = sort(tolist(var.read_only_principal_arns))
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${local.dns_suffix}"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values = [
          local.bucket_arn,
          "${local.bucket_arn}/*",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowReadWritePrincipalsViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = sort(tolist(var.read_write_principal_arns))
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${local.dns_suffix}"]
      }

      condition {
        test     = "StringLike"
        variable = "kms:EncryptionContext:aws:s3:arn"
        values = [
          local.bucket_arn,
          "${local.bucket_arn}/*",
        ]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_aws_log_delivery ? [1] : []
    content {
      sid    = "AllowAWSLogDeliveryKMS"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = "S3 encryption key for ${local.bucket_name} (${var.app_name} ${var.environment})"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  rotation_period_in_days = 365
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/s3/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.use_kms

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.use_kms ? "aws:kms" : "AES256"
      kms_master_key_id = local.effective_kms_key_arn
    }
  }
}

# -----------------------------------------------------------------------------
# Lifecycle & Cost Optimization
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket                                 = aws_s3_bucket.this.id
  transition_default_minimum_object_size = "all_storage_classes_128K"

  # Always clean up abandoned multipart uploads and orphaned delete markers
  rule {
    id     = "housekeeping"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.abort_incomplete_multipart_upload_days
    }

    dynamic "expiration" {
      for_each = var.object_expiration_days == null ? [1] : []
      content {
        expired_object_delete_marker = true
      }
    }
  }

  # Bound historical version storage costs
  dynamic "rule" {
    for_each = var.noncurrent_version_expiration_days != null ? [1] : []
    content {
      id     = "noncurrent-version-retention"
      status = "Enabled"

      filter {}

      dynamic "noncurrent_version_transition" {
        for_each = var.noncurrent_version_expiration_days >= 60 ? [1] : []
        content {
          noncurrent_days = 30
          storage_class   = "STANDARD_IA"
        }
      }

      noncurrent_version_expiration {
        noncurrent_days           = var.noncurrent_version_expiration_days
        newer_noncurrent_versions = var.noncurrent_versions_to_retain
      }
    }
  }

  # Automatically optimize storage costs for cold assets (>= 128 KB)
  dynamic "rule" {
    for_each = local.enable_intelligent_tiering_rule ? [1] : []
    content {
      id     = "intelligent-tiering"
      status = "Enabled"

      filter {}

      transition {
        days          = var.transition_to_intelligent_tiering_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  # Whole-bucket object expiration for ephemeral files / exports / logs
  dynamic "rule" {
    for_each = var.object_expiration_days != null ? [1] : []
    content {
      id     = "object-expiration"
      status = "Enabled"

      filter {}

      expiration {
        days = var.object_expiration_days
      }
    }
  }

  # Optional per-prefix lifecycle rules (e.g. "tmp/" or "exports/")
  dynamic "rule" {
    for_each = { for idx, r in var.prefix_lifecycle_rules : r.id => r }
    content {
      id     = "prefix-${rule.value.id}"
      status = "Enabled"

      filter {
        prefix = rule.value.prefix
      }

      dynamic "transition" {
        for_each = rule.value.transition_days != null ? [1] : []
        content {
          days          = rule.value.transition_days
          storage_class = rule.value.transition_storage_class
        }
      }

      dynamic "expiration" {
        for_each = rule.value.expiration_days != null ? [1] : []
        content {
          days = rule.value.expiration_days
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = rule.value.noncurrent_version_expiration_days != null ? [1] : []
        content {
          noncurrent_days = rule.value.noncurrent_version_expiration_days
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# -----------------------------------------------------------------------------
# Optional Integrations: CORS, Access Logging, EventBridge
# -----------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count  = length(var.cors_rules) > 0 ? 1 : 0
  bucket = aws_s3_bucket.this.id

  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      allowed_origins = cors_rule.value.allowed_origins
      allowed_methods = cors_rule.value.allowed_methods
      allowed_headers = cors_rule.value.allowed_headers
      expose_headers  = cors_rule.value.expose_headers
      max_age_seconds = cors_rule.value.max_age_seconds
    }
  }
}

resource "aws_s3_bucket_logging" "this" {
  count  = var.access_log_bucket_name != null ? 1 : 0
  bucket = aws_s3_bucket.this.id

  target_bucket = var.access_log_bucket_name
  target_prefix = coalesce(var.access_log_prefix, "${local.bucket_name}/")

  target_object_key_format {
    partitioned_prefix {
      partition_date_source = "EventTime"
    }
  }
}

resource "aws_s3_bucket_notification" "this" {
  count       = var.enable_eventbridge ? 1 : 0
  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# -----------------------------------------------------------------------------
# Bucket Policy (TLS Enforcement, Encryption Guardrails & Scoped Access)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "bucket_policy" {
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
    sid     = "DenyOutdatedTLS"
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

  # When SSE-KMS is configured, prevent callers from overriding encryption with AES256 or a foreign KMS key,
  # while still allowing standard SDK PutObject calls that omit SSE headers (handled by default bucket encryption).
  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "DenyNonKMSEncryptionAlgorithm"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption"
        values   = ["aws:kms"]
      }
    }
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid       = "DenyMismatchedKMSKey"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [local.effective_kms_key_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []
    content {
      sid       = "AllowCloudFrontOriginAccessControl"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = sort(tolist(var.cloudfront_distribution_arns))
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowReadOnlyPrincipals"
      effect = "Allow"
      actions = [
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:GetObjectVersion",
        "s3:ListBucket",
      ]
      resources = [
        local.bucket_arn,
        "${local.bucket_arn}/*",
      ]

      principals {
        type        = "AWS"
        identifiers = sort(tolist(var.read_only_principal_arns))
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []
    content {
      sid    = "AllowReadWritePrincipals"
      effect = "Allow"
      actions = [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:GetBucketLocation",
        "s3:GetObject",
        "s3:GetObjectTagging",
        "s3:GetObjectVersion",
        "s3:ListBucket",
        "s3:ListBucketMultipartUploads",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
        "s3:PutObjectTagging",
      ]
      resources = [
        local.bucket_arn,
        "${local.bucket_arn}/*",
      ]

      principals {
        type        = "AWS"
        identifiers = sort(tolist(var.read_write_principal_arns))
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_aws_log_delivery ? [1] : []
    content {
      sid       = "AllowAWSLogDeliveryWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }

  dynamic "statement" {
    for_each = var.allow_aws_log_delivery ? [1] : []
    content {
      sid       = "AllowAWSLogDeliveryAclCheck"
      effect    = "Allow"
      actions   = ["s3:GetBucketAcl"]
      resources = [local.bucket_arn]

      principals {
        type        = "Service"
        identifiers = ["delivery.logs.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceAccount"
        values   = [local.account_id]
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}
