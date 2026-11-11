# ---------------------------------------------------------------------------
# Bucket policy.
#
# Always present: every request must use HTTPS. Optionally, the module also
# grants read/write or read-only access to specific IAM principals, so app
# teams never have to write S3 IAM statements themselves.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "bucket_policy" {
  # Unconditional: refuse anything that is not TLS.
  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
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

  dynamic "statement" {
    for_each = length(var.read_only_principals) > 0 ? [1] : []

    content {
      sid       = "AllowReadOnlyPrincipalsOnBucket"
      effect    = "Allow"
      actions   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketVersions"]
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
      sid       = "AllowReadOnlyPrincipalsOnObjects"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:GetObjectVersion"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }
    }
  }

  # Read/write is a superset of read-only.
  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []

    content {
      sid       = "AllowReadWritePrincipalsOnBucket"
      effect    = "Allow"
      actions   = ["s3:GetBucketLocation", "s3:ListBucket", "s3:ListBucketVersions", "s3:ListBucketMultipartUploads"]
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
      sid    = "AllowReadWritePrincipalsOnObjects"
      effect = "Allow"
      actions = [
        "s3:AbortMultipartUpload",
        "s3:DeleteObject",
        "s3:DeleteObjectVersion",
        "s3:GetObject",
        "s3:GetObjectVersion",
        "s3:ListMultipartUploadParts",
        "s3:PutObject",
      ]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = data.aws_iam_policy_document.bucket_policy.json
}

# ---------------------------------------------------------------------------
# A ready-made IAM identity policy for application roles whose access is
# managed outside this module (e.g. via aws_iam_role_policy). Exposed as the
# `app_access_policy_json` output; includes key usage when SSE-KMS is on.
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "app_access" {
  statement {
    sid = "ListBucket"

    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketVersions",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ReadWriteObjects"

    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.kms_key_id != null ? [1] : []

    content {
      sid = "UseBucketEncryptionKey"

      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
      ]

      resources = [local.kms_key_id]
    }
  }
}
