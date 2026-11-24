data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketVersions",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "DecryptBucketObjects"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [local.effective_kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
      "s3:ListBucketMultipartUploads",
      "s3:ListBucketVersions",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:DeleteObjectTagging",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:GetObjectVersion",
      "s3:GetObjectVersionTagging",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "EncryptDecryptBucketObjects"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey",
        "kms:GenerateDataKeyWithoutPlaintext",
        "kms:ReEncrypt*",
      ]
      resources = [local.effective_kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = local.should_create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  path        = "/app-buckets/"
  description = "Read-only access to S3 bucket ${local.bucket_name} (${var.app_name} in ${var.environment})"
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.tags
}

resource "aws_iam_policy" "read_write" {
  count = local.should_create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  path        = "/app-buckets/"
  description = "Read-write access to S3 bucket ${local.bucket_name} (${var.app_name} in ${var.environment})"
  policy      = data.aws_iam_policy_document.read_write.json
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
