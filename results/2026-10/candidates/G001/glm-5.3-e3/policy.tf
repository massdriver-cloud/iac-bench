# Every request to this bucket must use TLS. Anything over plain HTTP is
# denied no matter who the caller is or what they are allowed to do otherwise.
data "aws_iam_policy_document" "deny_insecure_transport" {
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
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = data.aws_iam_policy_document.deny_insecure_transport.json

  depends_on = [aws_s3_bucket_public_access_block.this]
}

# Optional ready-made policy an application role can be granted, so teams
# don't have to write S3 IAM statements by hand.
data "aws_iam_policy_document" "app_access" {
  count = var.create_app_access_policy ? 1 : 0

  statement {
    sid = "ListBucket"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid = "ReadWriteObjects"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
      "s3:ListBucketMultipartUploads",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.uses_kms ? [local.kms_key_arn] : []

    content {
      sid = "UseEncryptionKey"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncryptFrom",
        "kms:ReEncryptTo",
      ]
      resources = [statement.value]
    }
  }
}

resource "aws_iam_policy" "app_access" {
  count = var.create_app_access_policy ? 1 : 0

  name        = "${local.bucket_name}-app-access"
  description = "Application read/write access to the ${local.bucket_name} S3 bucket (created by the app bucket module)."
  policy      = data.aws_iam_policy_document.app_access[0].json
  tags        = local.tags
}
