################################################################################
# Ready-to-Attach Least-Privilege Application IAM Policies
# Includes both S3 and KMS permissions so app roles never need hand-rolled JSON
################################################################################

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "BucketReadAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectReadAccess"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:GetObjectTagging",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "KMSDecryptAccess"
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
    sid    = "BucketReadWriteAccess"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  # Intentionally excludes s3:DeleteObjectVersion so compromised app credentials
  # cannot permanently purge version history.
  statement {
    sid    = "ObjectReadWriteAccess"
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
  }

  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "KMSReadWriteAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = [local.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "write_only" {
  statement {
    sid    = "BucketWriteAccess"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectWriteAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  # kms:Decrypt is required by AWS S3 for multipart uploads encrypted with SSE-KMS.
  dynamic "statement" {
    for_each = local.use_kms ? [1] : []

    content {
      sid    = "KMSWriteAccess"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
      ]
      resources = [local.kms_key_arn]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  description = "Least-privilege read-only access to S3 bucket ${local.bucket_name} and its encryption key."
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.common_tags
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  description = "Least-privilege read-write access to S3 bucket ${local.bucket_name} and its encryption key."
  policy      = data.aws_iam_policy_document.read_write.json
  tags        = local.common_tags
}

resource "aws_iam_policy" "write_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-write-only"
  description = "Least-privilege write-only access to S3 bucket ${local.bucket_name} and its encryption key."
  policy      = data.aws_iam_policy_document.write_only.json
  tags        = local.common_tags
}
