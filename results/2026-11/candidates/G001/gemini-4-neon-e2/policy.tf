data "aws_iam_policy_document" "bucket_policy" {
  source_policy_documents = var.additional_bucket_policy_json != null ? [var.additional_bucket_policy_json] : []

  # 1. Enforce HTTPS/TLS for every S3 API call (in-transit encryption).
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

  # 2. Enforce TLS 1.2 or higher.
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

  # 3. Prevent encryption downgrade attacks without breaking clients that rely on default encryption.
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
      values   = [local.expected_sse_algorithm]
    }
  }

  # 4. Optional read-only principals (bucket listing + object reads).
  dynamic "statement" {
    for_each = length(var.read_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadPrincipalsBucket"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.read_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_principal_arns) > 0 ? [1] : []

    content {
      sid       = "AllowReadPrincipalsObjects"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.read_principal_arns
      }
    }
  }

  # 5. Optional read-write principals (bucket listing + object read/write/delete/multipart).
  dynamic "statement" {
    for_each = length(var.write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowWritePrincipalsBucket"
      effect = "Allow"
      actions = [
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:ListBucketMultipartUploads",
      ]
      resources = [aws_s3_bucket.this.arn]

      principals {
        type        = "AWS"
        identifiers = var.write_principal_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowWritePrincipalsObjects"
      effect = "Allow"
      actions = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:AbortMultipartUpload",
        "s3:ListMultipartUploadParts",
      ]
      resources = ["${aws_s3_bucket.this.arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.write_principal_arns
      }
    }
  }

  # 6. Optional CloudFront Origin Access Control (OAC) read access.
  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontOAC"
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
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.bucket_policy.json

  depends_on = [
    aws_s3_bucket_public_access_block.this,
    aws_s3_bucket_ownership_controls.this,
  ]
}
