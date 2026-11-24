data "aws_partition" "current" {}

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"

    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]

    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []

    content {
      sid    = "DecryptWithBucketKMS"
      effect = "Allow"

      actions   = ["kms:Decrypt"]
      resources = [statement.value]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"

    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]

    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadWriteObjects"
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
    for_each = var.kms_key_arn != null ? [var.kms_key_arn] : []

    content {
      sid    = "UseBucketKMS"
      effect = "Allow"

      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]

      resources = [statement.value]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  description = "Least-privilege read-only access to ${local.bucket_name}."
  policy      = data.aws_iam_policy_document.read_only.json

  tags = local.common_tags
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  description = "Least-privilege read-write object access to ${local.bucket_name}."
  policy      = data.aws_iam_policy_document.read_write.json

  tags = local.common_tags
}
