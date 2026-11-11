###############################################################################
# Ready-made, least-privilege access policies
#
# App teams should never have to write S3/KMS IAM by hand. They either pass
# their role names in (read_write_role_names / read_only_role_names) or attach
# the policy ARNs from the outputs themselves.
###############################################################################

data "aws_iam_policy_document" "read_only" {
  statement {
    sid    = "ListBucket"
    effect = "Allow"
    actions = [
      "s3:GetBucketLocation",
      "s3:ListBucket",
    ]
    resources = [local.bucket_arn]
  }

  statement {
    sid    = "ReadObjects"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid       = "DecryptViaS3Only"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
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
    ]
    resources = [local.bucket_arn]
  }

  # Note what is *not* here: s3:DeleteObjectVersion. Applications can delete
  # objects, but the previous version stays recoverable for
  # var.deleted_object_recovery_days - a compromised or buggy app cannot
  # permanently destroy data.
  statement {
    sid    = "ReadWriteObjects"
    effect = "Allow"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:DeleteObject",
      "s3:GetObject",
      "s3:GetObjectTagging",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
      "s3:PutObjectTagging",
    ]
    resources = ["${local.bucket_arn}/*"]
  }

  statement {
    sid    = "EncryptDecryptViaS3Only"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey",
    ]
    resources = [local.kms_key_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["s3.${local.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "read_only" {
  name        = "${local.bucket_name}-read-only"
  description = "List and download objects in S3 bucket ${local.bucket_name}"
  policy      = data.aws_iam_policy_document.read_only.json

  tags = local.tags
}

resource "aws_iam_policy" "read_write" {
  name        = "${local.bucket_name}-read-write"
  description = "List, download, upload and delete objects in S3 bucket ${local.bucket_name}"
  policy      = data.aws_iam_policy_document.read_write.json

  tags = local.tags
}

# Attachments wait for the bucket so a role never holds a policy for a bucket
# name that does not exist yet (and could be claimed by someone else).
resource "aws_iam_role_policy_attachment" "read_only" {
  for_each = toset(var.read_only_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.read_only.arn

  depends_on = [aws_s3_bucket.this]
}

resource "aws_iam_role_policy_attachment" "read_write" {
  for_each = toset(var.read_write_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.read_write.arn

  depends_on = [aws_s3_bucket.this]
}
