# ------------------------------------------------------------------------------
# Least-Privilege Application IAM Policies (Read-Only & Read-Write)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "app_read_only" {
  statement {
    sid    = "BucketListAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid    = "ObjectReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
      "s3:GetObjectAttributes"
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = local.kms_enabled ? [1] : []

    content {
      sid    = "BucketKmsDecryptAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey"
      ]
      resources = [local.effective_kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [local.s3_via_service]
      }
    }
  }
}

data "aws_iam_policy_document" "app_read_write" {
  statement {
    sid    = "BucketListAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads"
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid    = "ObjectReadWriteAccess"
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
  }

  dynamic "statement" {
    for_each = local.kms_enabled ? [1] : []

    content {
      sid    = "BucketKmsReadWriteAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
        "kms:DescribeKey"
      ]
      resources = [local.effective_kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = [local.s3_via_service]
      }
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  path        = "/app-buckets/${var.environment}/"
  description = "Least-privilege read-only S3 access to ${local.bucket_name} (${var.app_name} ${var.environment})"
  policy      = data.aws_iam_policy_document.app_read_only.json
  tags        = local.tags
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  path        = "/app-buckets/${var.environment}/"
  description = "Least-privilege read-write S3 access to ${local.bucket_name} (${var.app_name} ${var.environment})"
  policy      = data.aws_iam_policy_document.app_read_write.json
  tags        = local.tags
}
