# --- Application IAM Integration ---
# Pre-packaged, least-privilege IAM policies designed for application compute
# (ECS task roles, Lambda execution roles, EKS service accounts, EC2 instance profiles).

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "S3ReadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSDecryptKey"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "S3ListBucket"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "S3ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:DeleteObjectVersion",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSDecryptAndGenerateDataKey"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

data "aws_iam_policy_document" "write_only" {
  statement {
    sid    = "S3ListBucketMultipartUploads"
    effect = "Allow"
    actions = [
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "S3WriteObjects"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = var.kms_key_arn != null ? [1] : []
    content {
      sid    = "KMSEncryptKey"
      effect = "Allow"
      actions = [
        "kms:GenerateDataKey",
        "kms:DescribeKey",
      ]
      resources = [var.kms_key_arn]
    }
  }
}

locals {
  iam_policy_prefix = coalesce(var.iam_policy_name_prefix, var.bucket_name)
}

resource "aws_iam_policy" "read_only" {
  count       = var.create_iam_access_policies ? 1 : 0
  name        = "${local.iam_policy_prefix}-s3-read-only"
  description = "Read-only access to S3 bucket ${var.bucket_name} and its assets"
  policy      = data.aws_iam_policy_document.read_only.json
  tags        = local.merged_tags
}

resource "aws_iam_policy" "read_write" {
  count       = var.create_iam_access_policies ? 1 : 0
  name        = "${local.iam_policy_prefix}-s3-read-write"
  description = "Read and write access to S3 bucket ${var.bucket_name} and its assets"
  policy      = data.aws_iam_policy_document.read_write.json
  tags        = local.merged_tags
}

resource "aws_iam_policy" "write_only" {
  count       = var.create_iam_access_policies ? 1 : 0
  name        = "${local.iam_policy_prefix}-s3-write-only"
  description = "Write-only (upload/ingest) access to S3 bucket ${var.bucket_name}"
  policy      = data.aws_iam_policy_document.write_only.json
  tags        = local.merged_tags
}
