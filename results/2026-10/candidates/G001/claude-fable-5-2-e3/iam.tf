###############################################################################
# Ready-made access policies
#
# The bucket is private and KMS-encrypted, so an application needs both S3 and
# KMS permissions. Rather than have every team work that out, the module
# publishes two least-privilege policies to attach to the application's role.
#
# Neither policy can permanently delete data: "delete" only hides the current
# version, which stays recoverable for the retention period.
###############################################################################

data "aws_iam_policy_document" "read_only" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid       = "ReadObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "DecryptViaS3Only"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

data "aws_iam_policy_document" "read_write" {
  statement {
    sid       = "ListBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:GetBucketLocation", "s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:AbortMultipartUpload",
      "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "EncryptDecryptViaS3Only"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-only"
  description = "List and read objects in S3 bucket ${local.bucket_name}"
  policy      = data.aws_iam_policy_document.read_only.json

  tags = local.tags
}

resource "aws_iam_policy" "read_write" {
  count = var.create_iam_policies ? 1 : 0

  name        = "${local.bucket_name}-read-write"
  description = "List, read, write and (recoverably) delete objects in S3 bucket ${local.bucket_name}"
  policy      = data.aws_iam_policy_document.read_write.json

  tags = local.tags
}
