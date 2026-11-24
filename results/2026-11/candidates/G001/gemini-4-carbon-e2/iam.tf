# -----------------------------------------------------------------------------
# Least-Privilege Application IAM Policies (Read-Only & Read-Write)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "app_read_only" {
  statement {
    sid    = "BucketMetadataAndList"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid    = "ObjectRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid    = "KMSDecryptViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [local.effective_kms_key_arn]

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
}

data "aws_iam_policy_document" "app_read_write" {
  statement {
    sid    = "BucketMetadataAndList"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid    = "ObjectReadWrite"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []
    content {
      sid    = "KMSEncryptDecryptViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
      ]
      resources = [local.effective_kms_key_arn]

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
}

resource "aws_iam_policy" "read_only" {
  count = local.should_create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-ro"
  description = "Least-privilege read-only S3 access to ${local.bucket_name} (${var.app_name} ${var.environment})"
  policy      = data.aws_iam_policy_document.app_read_only.json
  tags        = local.tags
}

resource "aws_iam_policy" "read_write" {
  count = local.should_create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-rw"
  description = "Least-privilege read-write S3 access to ${local.bucket_name} (${var.app_name} ${var.environment})"
  policy      = data.aws_iam_policy_document.app_read_write.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "read_only" {
  for_each = var.read_only_iam_role_names

  role       = each.value
  policy_arn = aws_iam_policy.read_only[0].arn
}

resource "aws_iam_role_policy_attachment" "read_write" {
  for_each = var.read_write_iam_role_names

  role       = each.value
  policy_arn = aws_iam_policy.read_write[0].arn
}
