data "aws_iam_policy_document" "bucket_policy" {
  source_policy_documents = var.additional_bucket_policy_json != null ? [var.additional_bucket_policy_json] : []

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

  dynamic "statement" {
    for_each = var.enforce_tls_1_2 ? [1] : []

    content {
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
  }

  # Prevents callers from downgrading encryption by explicitly requesting a weaker
  # algorithm, while still allowing standard SDK PutObject calls that omit encryption
  # headers and rely on S3's bucket default encryption.
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
      test     = "StringNotEqualsIfExists"
      variable = "s3:x-amz-server-side-encryption"
      values   = [local.use_kms ? "aws:kms" : "AES256"]
    }
  }

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
        test     = "StringNotEqualsIfExists"
        variable = "s3:x-amz-server-side-encryption-aws-kms-key-id"
        values   = [local.kms_key_arn]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontOACRead"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

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
    for_each = length(var.read_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyBucketAccess"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyObjectAccess"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
      ]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadWriteBucketAccess"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadWriteObjectAccess"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:GetObjectTagging",
        "s3:PutObject",
        "s3:PutObjectTagging",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.write_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowWriteOnlyBucketAccess"
      effect = "Allow"
      actions = [
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.write_only_principals
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.write_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowWriteOnlyObjectAccess"
      effect = "Allow"
      actions = [
        "s3:PutObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.write_only_principals
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
