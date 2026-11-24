locals {
  bucket_name = coalesce(var.bucket, var.bucket_name)

  effective_tags = merge(
    {
      "Name"      = coalesce(var.bucket, var.bucket_name)
      "ManagedBy" = "OpenTofu"
    },
    var.environment != null ? { "Environment" = var.environment } : {},
    var.application != null ? { "Application" = var.application } : {},
    var.tags
  )

  extra_policy_docs = concat(
    var.custom_policy_json != null ? [var.custom_policy_json] : [],
    var.custom_policy_documents
  )

  create_bucket_policy = (
    var.enforce_tls ||
    length(var.read_only_principals) > 0 ||
    length(var.read_write_principals) > 0 ||
    length(var.cloudfront_distribution_arns) > 0 ||
    length(local.extra_policy_docs) > 0
  )

  has_lifecycle_rules = (
    var.abort_incomplete_multipart_upload_days != null ||
    (var.versioning_enabled && var.noncurrent_version_expiration_days != null) ||
    (var.versioning_enabled && var.noncurrent_version_transition_days != null) ||
    (var.versioning_enabled && var.clean_expired_object_delete_markers) ||
    var.expiration_days != null ||
    var.transition_days != null ||
    length(var.custom_lifecycle_rules) > 0
  )

  has_cors_rules = length(var.cors_rules) > 0 || length(var.cors_allowed_origins) > 0
}

# -----------------------------------------------------------------------------
# Core S3 Bucket
# -----------------------------------------------------------------------------
resource "aws_s3_bucket" "this" {
  bucket        = local.bucket_name
  force_destroy = var.force_destroy
  tags          = local.effective_tags
}

# -----------------------------------------------------------------------------
# Bucket Ownership Controls: Disables ACLs and enforces bucket owner ownership
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = var.object_ownership
  }
}

# -----------------------------------------------------------------------------
# Block Public Access: Prevents accidental public exposure of application data
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = var.block_public_access
  block_public_policy     = var.block_public_access
  ignore_public_acls      = var.block_public_access
  restrict_public_buckets = var.block_public_access
}

# -----------------------------------------------------------------------------
# Server-Side Encryption: Default SSE-S3 or customer-managed SSE-KMS
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.kms_key_arn != null ? "aws:kms" : "AES256"
      kms_master_key_id = var.kms_key_arn
    }
    bucket_key_enabled = var.bucket_key_enabled
  }
}

# -----------------------------------------------------------------------------
# Versioning: Protects against accidental deletion or overwrite of assets
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = var.versioning_enabled ? "Enabled" : "Suspended"
  }
}

# -----------------------------------------------------------------------------
# Lifecycle Configuration: Prevents storage cost runaway
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_lifecycle_configuration" "this" {
  count = local.has_lifecycle_rules ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Rule: Abort incomplete multipart uploads (critical for failed media/file uploads)
  dynamic "rule" {
    for_each = var.abort_incomplete_multipart_upload_days != null ? [1] : []
    content {
      id     = "abort-incomplete-multipart-uploads"
      status = "Enabled"

      filter {}

      abort_incomplete_multipart_upload {
        days_after_initiation = var.abort_incomplete_multipart_upload_days
      }
    }
  }

  # Rule: Expire non-current versions after retention window
  dynamic "rule" {
    for_each = var.versioning_enabled && var.noncurrent_version_expiration_days != null ? [1] : []
    content {
      id     = "expire-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_expiration {
        noncurrent_days = var.noncurrent_version_expiration_days
      }
    }
  }

  # Rule: Transition non-current versions to cheaper storage (Standard-IA)
  dynamic "rule" {
    for_each = var.versioning_enabled && var.noncurrent_version_transition_days != null ? [1] : []
    content {
      id     = "transition-noncurrent-versions"
      status = "Enabled"

      filter {}

      noncurrent_version_transition {
        noncurrent_days = var.noncurrent_version_transition_days
        storage_class   = var.noncurrent_version_transition_storage_class
      }
    }
  }

  # Rule: Remove expired object delete markers when versions are deleted
  dynamic "rule" {
    for_each = var.versioning_enabled && var.clean_expired_object_delete_markers ? [1] : []
    content {
      id     = "cleanup-expired-delete-markers"
      status = "Enabled"

      filter {}

      expiration {
        expired_object_delete_marker = true
      }
    }
  }

  # Rule: Expire current objects (useful for temporary files and logs)
  dynamic "rule" {
    for_each = var.expiration_days != null ? [1] : []
    content {
      id     = "expire-current-objects"
      status = "Enabled"

      filter {}

      expiration {
        days = var.expiration_days
      }
    }
  }

  # Rule: Transition current objects to cheaper storage tiers
  dynamic "rule" {
    for_each = var.transition_days != null ? [1] : []
    content {
      id     = "transition-current-objects"
      status = "Enabled"

      filter {}

      transition {
        days          = var.transition_days
        storage_class = var.transition_storage_class
      }
    }
  }

  # Custom lifecycle rules supplied by caller
  dynamic "rule" {
    for_each = var.custom_lifecycle_rules
    content {
      id     = rule.value.id
      status = lookup(rule.value, "status", "Enabled")

      dynamic "filter" {
        for_each = lookup(rule.value, "filter", null) != null ? [rule.value.filter] : [1]
        content {
          prefix = lookup(filter.value, "prefix", null)
        }
      }

      dynamic "expiration" {
        for_each = lookup(rule.value, "expiration", null) != null ? [rule.value.expiration] : []
        content {
          days                         = lookup(expiration.value, "days", null)
          date                         = lookup(expiration.value, "date", null)
          expired_object_delete_marker = lookup(expiration.value, "expired_object_delete_marker", null)
        }
      }

      dynamic "transition" {
        for_each = lookup(rule.value, "transition", null) != null ? (can(rule.value.transition[0]) ? rule.value.transition : [rule.value.transition]) : []
        content {
          days          = lookup(transition.value, "days", null)
          date          = lookup(transition.value, "date", null)
          storage_class = transition.value.storage_class
        }
      }

      dynamic "noncurrent_version_expiration" {
        for_each = lookup(rule.value, "noncurrent_version_expiration", null) != null ? [rule.value.noncurrent_version_expiration] : []
        content {
          noncurrent_days = noncurrent_version_expiration.value.noncurrent_days
        }
      }

      dynamic "noncurrent_version_transition" {
        for_each = lookup(rule.value, "noncurrent_version_transition", null) != null ? (can(rule.value.noncurrent_version_transition[0]) ? rule.value.noncurrent_version_transition : [rule.value.noncurrent_version_transition]) : []
        content {
          noncurrent_days = noncurrent_version_transition.value.noncurrent_days
          storage_class   = noncurrent_version_transition.value.storage_class
        }
      }

      dynamic "abort_incomplete_multipart_upload" {
        for_each = lookup(rule.value, "abort_incomplete_multipart_upload", null) != null ? [rule.value.abort_incomplete_multipart_upload] : []
        content {
          days_after_initiation = abort_incomplete_multipart_upload.value.days_after_initiation
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

# -----------------------------------------------------------------------------
# Bucket Policy: TLS enforcement, least-privilege role access, CloudFront OAC
# -----------------------------------------------------------------------------
data "aws_iam_policy_document" "bucket_policy" {
  count = local.create_bucket_policy ? 1 : 0

  source_policy_documents = local.extra_policy_docs

  # Deny all plain HTTP requests (TLS in-transit encryption requirement)
  dynamic "statement" {
    for_each = var.enforce_tls ? [1] : []
    content {
      sid     = "EnforceTLSRequestsOnly"
      effect  = "Deny"
      actions = ["s3:*"]
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
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
  }

  # Deny legacy TLS versions (< TLS 1.2)
  dynamic "statement" {
    for_each = var.enforce_tls && var.minimum_tls_version != null ? [1] : []
    content {
      sid     = "EnforceMinimumTLSVersion"
      effect  = "Deny"
      actions = ["s3:*"]
      resources = [
        aws_s3_bucket.this.arn,
        "${aws_s3_bucket.this.arn}/*",
      ]
      principals {
        type        = "*"
        identifiers = ["*"]
      }
      condition {
        test     = "NumericLessThan"
        variable = "s3:TlsVersion"
        values   = [var.minimum_tls_version]
      }
    }
  }

  # Read-only access for specified IAM principals (objects)
  dynamic "statement" {
    for_each = length(var.read_only_principals) > 0 ? [1] : []
    content {
      sid    = "AllowReadOnlyObjectAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
      ]
      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }

  # Read-only access for specified IAM principals (bucket listings)
  dynamic "statement" {
    for_each = length(var.read_only_principals) > 0 ? [1] : []
    content {
      sid    = "AllowReadOnlyBucketAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }
      actions = [
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
      ]
      resources = [
        aws_s3_bucket.this.arn,
      ]
    }
  }

  # Read-write access for specified IAM principals (objects)
  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []
    content {
      sid    = "AllowReadWriteObjectAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:AbortMultipartUpload",
      ]
      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]
    }
  }

  # Read-write access for specified IAM principals (bucket listings)
  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []
    content {
      sid    = "AllowReadWriteBucketAccess"
      effect = "Allow"
      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }
      actions = [
        "s3:ListBucket",
        "s3:ListBucketVersions",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]
      resources = [
        aws_s3_bucket.this.arn,
      ]
    }
  }

  # CloudFront Origin Access Control (OAC) read access
  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []
    content {
      sid    = "AllowCloudFrontOACReadOnly"
      effect = "Allow"
      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }
      actions = [
        "s3:GetObject",
      ]
      resources = [
        "${aws_s3_bucket.this.arn}/*",
      ]
      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  count = local.create_bucket_policy ? 1 : 0

  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy[0].json

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}

# -----------------------------------------------------------------------------
# CORS Configuration: For web and mobile uploads / downloads
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_cors_configuration" "this" {
  count = local.has_cors_rules ? 1 : 0

  bucket = aws_s3_bucket.this.id

  # Custom CORS rules if provided
  dynamic "cors_rule" {
    for_each = var.cors_rules
    content {
      id              = lookup(cors_rule.value, "id", null)
      allowed_headers = lookup(cors_rule.value, "allowed_headers", ["*"])
      allowed_methods = cors_rule.value.allowed_methods
      allowed_origins = cors_rule.value.allowed_origins
      expose_headers  = lookup(cors_rule.value, "expose_headers", null)
      max_age_seconds = lookup(cors_rule.value, "max_age_seconds", null)
    }
  }

  # Standard CORS rule if origins specified and no custom rules provided
  dynamic "cors_rule" {
    for_each = length(var.cors_rules) == 0 && length(var.cors_allowed_origins) > 0 ? [1] : []
    content {
      id              = "standard-app-cors-rule"
      allowed_headers = var.cors_allowed_headers
      allowed_methods = var.cors_allowed_methods
      allowed_origins = var.cors_allowed_origins
      expose_headers  = var.cors_expose_headers
      max_age_seconds = var.cors_max_age_seconds
    }
  }
}

# -----------------------------------------------------------------------------
# Server Access Logging: Optional audit logging
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_logging" "this" {
  count = var.logging_target_bucket != null ? 1 : 0

  bucket        = aws_s3_bucket.this.id
  target_bucket = var.logging_target_bucket
  target_prefix = var.logging_target_prefix != null ? var.logging_target_prefix : "s3-access-logs/${local.bucket_name}/"
}

# -----------------------------------------------------------------------------
# Intelligent Tiering: Cost optimization for variable access patterns
# -----------------------------------------------------------------------------
resource "aws_s3_bucket_intelligent_tiering_configuration" "this" {
  count = var.enable_intelligent_tiering ? 1 : 0

  bucket = aws_s3_bucket.this.id
  name   = "EntireBucketTiering"

  tiering {
    access_tier = "ARCHIVE_ACCESS"
    days        = 90
  }

  tiering {
    access_tier = "DEEP_ARCHIVE_ACCESS"
    days        = 180
  }
}
