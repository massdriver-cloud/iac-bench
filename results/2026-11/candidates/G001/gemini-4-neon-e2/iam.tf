# ------------------------------------------------------------------------------
# Least-Privilege IAM Policies for Application Roles (ECS, EKS, Lambda, EC2)
# Automatically include scoped KMS permissions so app teams never hit KMS errors
# and never resort to AmazonS3FullAccess.
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "BucketMetadataAndList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ObjectRead"
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
      sid    = "KmsDecryptViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = [local.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid    = "BucketMetadataAndList"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketLocation",
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.this.arn]
  }

  # Intentionally excludes s3:DeleteObjectVersion, s3:DeleteBucket, and policy/ACL mutation
  # so a compromised app role cannot purge version history or expose the bucket.
  statement {
    sid    = "ObjectReadWrite"
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
      sid    = "KmsEncryptDecryptViaS3"
      effect = "Allow"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = [local.kms_key_arn]

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "s3-${local.bucket_name}-read-only"
  description = "Least-privilege read-only access to S3 bucket ${local.bucket_name} and its encryption key."
  policy      = data.aws_iam_policy_document.read_only.json

  tags = merge(local.common_tags, {
    Name = "s3-${local.bucket_name}-read-only"
  })
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "s3-${local.bucket_name}-read-write"
  description = "Least-privilege read-write access to S3 bucket ${local.bucket_name} and its encryption key."
  policy      = data.aws_iam_policy_document.read_write.json

  tags = merge(local.common_tags, {
    Name = "s3-${local.bucket_name}-read-write"
  })
}
