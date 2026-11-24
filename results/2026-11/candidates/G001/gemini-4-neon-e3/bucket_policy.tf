data "aws_iam_policy_document" "bucket_policy" {
  source_policy_documents = compact([var.additional_bucket_policy_json])

  # 1. Always require HTTPS (TLS) for every request.
  statement {
    sid     = "DenyInsecureTransport"
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

  # 2. Enforce TLS 1.2 or newer.
  statement {
    sid     = "DenyOutdatedTLS"
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
      values   = ["1.2"]
    }
  }

  # 3. Prevent callers from explicitly downgrading server-side encryption on upload,
  # while still allowing standard SDK/presigned uploads that omit the header (which
  # automatically inherit the bucket's default encryption).
  statement {
    sid       = "DenyIncorrectEncryptionHeader"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]

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
      values   = [local.sse_algorithm]
    }
  }

  # 4. When KMS encryption is enabled, prevent callers from explicitly specifying
  # a different KMS key than the bucket's designated key.
  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid       = "DenyIncorrectKMSKey"
      effect    = "Deny"
      actions   = ["s3:PutObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

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
        test     = "ArnNotEquals"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [local.kms_key_arn]
      }
    }
  }

  # 5. Optional CloudFront Origin Access Control (OAC) read-only access for serving
  # media/assets publicly through CloudFront while keeping S3 completely private.
  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontServicePrincipalReadOnly"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  # 6. Optional explicit read-only IAM principals (e.g. cross-account roles).
  dynamic "statement" {
    for_each = length(var.allowed_read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsBucket"
      effect = "Allow"
      actions = concat(
        [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ],
        local.versioning_enabled ? ["s3:ListBucketVersions"] : []
      )
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_only_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsObjects"
      effect = "Allow"
      actions = concat(
        [
          "s3:GetObject",
          "s3:GetObjectAttributes",
          "s3:GetObjectTagging",
        ],
        local.versioning_enabled ? [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAttributes",
          "s3:GetObjectVersionTagging",
        ] : []
      )
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_only_principal_arns
      }
    }
  }

  # 7. Optional explicit read-write IAM principals (e.g. cross-account roles).
  dynamic "statement" {
    for_each = length(var.allowed_read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsBucket"
      effect = "Allow"
      actions = concat(
        [
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:ListBucketMultipartUploads",
        ],
        local.versioning_enabled ? ["s3:ListBucketVersions"] : []
      )
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_write_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.allowed_read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsObjects"
      effect = "Allow"
      actions = concat(
        [
          "s3:GetObject",
          "s3:GetObjectAttributes",
          "s3:GetObjectTagging",
          "s3:PutObject",
          "s3:PutObjectTagging",
          "s3:DeleteObject",
          "s3:DeleteObjectTagging",
          "s3:AbortMultipartUpload",
          "s3:ListMultipartUploadParts",
        ],
        local.versioning_enabled ? [
          "s3:GetObjectVersion",
          "s3:GetObjectVersionAttributes",
          "s3:GetObjectVersionTagging",
        ] : []
      )
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_write_principal_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}
