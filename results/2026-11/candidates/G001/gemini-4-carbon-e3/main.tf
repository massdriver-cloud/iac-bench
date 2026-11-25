data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_partition" "current" {}

locals {
  account_id     = data.aws_caller_identity.current.account_id
  region         = data.aws_region.current.name
  partition      = data.aws_partition.current.partition
  dns_suffix     = data.aws_partition.current.dns_suffix
  s3_via_service = "s3.${local.region}.${local.dns_suffix}"

  base_prefix    = "${var.app_name}-${var.purpose}-${var.environment}"
  uniqueness_tag = "${local.account_id}-${local.region}"
  full_candidate = "${local.base_prefix}-${local.uniqueness_tag}"

  # Keep bucket name readable when <= 63 chars; deterministically truncate + hash prefix if longer.
  max_trimmed_prefix_len = 63 - 1 - length(local.uniqueness_tag) - 7
  generated_bucket_name = (
    length(local.full_candidate) <= 63
    ? local.full_candidate
    : "${trimsuffix(substr(local.base_prefix, 0, local.max_trimmed_prefix_len), "-")}-${substr(sha256(local.base_prefix), 0, 6)}-${local.uniqueness_tag}"
  )

  bucket_name           = var.bucket_name_override != null ? var.bucket_name_override : local.generated_bucket_name
  bucket_arn            = "arn:${local.partition}:s3:::${local.bucket_name}"
  kms_enabled           = var.create_kms_key || var.kms_key_arn != null
  effective_kms_key_arn = var.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn

  # Only enable Intelligent-Tiering if objects won't expire before (or on) the transition day.
  enable_intelligent_tiering_rule = (
    var.lifecycle_rules.enable_intelligent_tiering && (
      var.lifecycle_rules.expiration_days == null ||
      var.lifecycle_rules.expiration_days > var.lifecycle_rules.intelligent_tiering_days
    )
  )

  default_tags = {
    Application = var.app_name
    Environment = var.environment
    Purpose     = var.purpose
    ManagedBy   = "opentofu"
  }

  tags = merge(local.default_tags, var.tags)
}

# ------------------------------------------------------------------------------
# Optional Dedicated Customer-Managed KMS Key
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_key" {
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
        "kms:GenerateDataKey*"
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principal_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [local.s3_via_service]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsCrypto"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
        "kms:DescribeKey"
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principal_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [local.s3_via_service]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = "S3 encryption key for ${local.bucket_name} (${var.app_name} ${var.environment})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key[0].json
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/s3/${replace(local.bucket_name, ".", "-")}"
  target_key_id = aws_kms_key.this[0].key_id
}

# ------------------------------------------------------------------------------
# S3 Bucket & Security Baseline
# ------------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.tags

  lifecycle {
    precondition {
      condition     = !(var.create_kms_key && var.kms_key_arn != null)
      error_message = "create_kms_key and kms_key_arn are mutually exclusive: either set create_kms_key = true or supply an existing kms_key_arn, not both."
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

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = local.kms_enabled

    apply_server_side_encryption_by_default {
      sse_algorithm     = local.kms_enabled ? "aws:kms" : "AES256"
      kms_master_key_id = local.effective_kms_key_arn
    }
  }
}

# ------------------------------------------------------------------------------
# Lifecycle Management & Cost Optimization
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket                                 = aws_s3_bucket.this.id
  transition_default_minimum_object_size = "all_storage_classes_128K"

  depends_on = [aws_s3_bucket_versioning.this]

  rule {
    id     = "housekeeping-multipart-and-delete-markers"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = var.lifecycle_rules.abort_incomplete_multipart_upload_days
    }

    dynamic "expiration" {
      for_each = var.lifecycle_rules.expiration_days == null ? [1] : []

      content {
        expired_object_delete_marker = true
      }
    }
  }

  rule {
    id     = "noncurrent-version-cleanup"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days           = var.lifecycle_rules.noncurrent_version_expiration_days
      newer_noncurrent_versions = var.lifecycle_rules.noncurrent_versions_to_retain
    }
  }

  dynamic "rule" {
    for_each = local.enable_intelligent_tiering_rule ? [1] : []

    content {
      id     = "intelligent-tiering-cost-optimization"
      status = "Enabled"

      filter {}

      transition {
        days          = var.lifecycle_rules.intelligent_tiering_days
        storage_class = "INTELLIGENT_TIERING"
      }
    }
  }

  dynamic "rule" {
    for_each = var.lifecycle_rules.expiration_days != null ? [1] : []

    content {
      id     = "object-expiration"
      status = "Enabled"

      filter {}

      expiration {
        days = var.lifecycle_rules.expiration_days
      }
    }
  }
}

# ------------------------------------------------------------------------------
# Optional CORS, Server Access Logging, & EventBridge Notifications
# ------------------------------------------------------------------------------

resource "aws_s3_bucket_cors_configuration" "this" {
  count = length(var.cors_rules) > 0 ? 1 : 0

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
  count = var.access_logging != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.access_logging.target_bucket
  target_prefix = var.access_logging.target_prefix != null ? var.access_logging.target_prefix : "${local.bucket_name}/"
}

resource "aws_s3_bucket_notification" "this" {
  count = var.enable_eventbridge ? 1 : 0

  bucket      = aws_s3_bucket.this.id
  eventbridge = true
}

# ------------------------------------------------------------------------------
# Bucket Policy (TLS Enforcement, Encryption Guardrails, & Principal Access)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "bucket_policy" {
  statement {
    sid     = "DenyInsecureTransport"
    effect  = "Deny"
    actions = ["s3:*"]

    resources = [
      local.bucket_arn,
      "${local.bucket_arn}/*"
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
      "${local.bucket_arn}/*"
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

  # When customer-managed KMS encryption is active, reject explicit non-KMS headers or mismatched KMS keys
  # while still permitting standard SDK/presigned uploads that omit headers and rely on bucket default encryption.
  dynamic "statement" {
    for_each = local.kms_enabled ? [1] : []

    content {
      sid       = "DenyNonKmsEncryptionOverride"
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

  dynamic "statement" {
    for_each = local.kms_enabled ? [1] : []

    content {
      sid       = "DenyMismatchedKmsKeyOverride"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "*"
        identifiers = ["*"]
      }

      condition {
        test     = "Null"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = ["false"]
      }

      condition {
        test     = "StringNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [local.effective_kms_key_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontOACRead"
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
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsList"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ]
      resources = [local.bucket_arn]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsObjectRead"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
        "s3:GetObjectAttributes"
      ]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsList"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads"
      ]
      resources = [local.bucket_arn]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsObjectReadWrite"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
        "s3:GetObjectAttributes",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts"
      ]
      resources = ["${local.bucket_arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principal_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this
  ]
}
