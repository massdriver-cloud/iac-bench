################################################################################
# Ready-to-Attach Least-Privilege Application IAM Policies
################################################################################

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "BucketReadMetadata"
    effect = "Allow"
    actions = concat(
      [
        "s3:ListBucket",
        "s3:GetBucketLocation",
      ],
      local.versioning_enabled ? ["s3:ListBucketVersions"] : []
    )
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectRead"
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
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "KMSDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [local.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "BucketReadAndMultipartMetadata"
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
  }

  # Intentionally excludes s3:DeleteObjectVersion so application roles cannot
  # permanently purge version history, and excludes all bucket-admin actions.
  statement {
    sid    = "ObjectReadWrite"
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
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "KMSEncryptDecrypt"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
      ]
      resources = [local.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  description = "Least-privilege read-only access to S3 bucket ${local.bucket_name} (including KMS decrypt if enabled)."
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.common_tags
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  description = "Least-privilege read-write access to S3 bucket ${local.bucket_name} (including KMS encrypt/decrypt if enabled)."
  policy      = data.aws_iam_policy_document.read_write.json
  tags        = local.common_tags
}
