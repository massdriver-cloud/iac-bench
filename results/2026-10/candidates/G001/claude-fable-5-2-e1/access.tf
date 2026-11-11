# -----------------------------------------------------------------------------
# Least-privilege access for the application.
#
# Both policy documents are also exposed as outputs for principals the module
# cannot attach to directly (users, permission sets, roles managed elsewhere).
# -----------------------------------------------------------------------------

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
    sid       = "DecryptObjects"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [local.kms_key_arn]
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

  # Deliberately no s3:DeleteObjectVersion: the application can delete files,
  # but a delete only hides the current version, so mistakes (and compromised
  # credentials) stay recoverable for the version retention window.
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
    sid       = "EncryptDecryptObjects"
    effect    = "Allow"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey"]
    resources = [local.kms_key_arn]
  }
}

resource "aws_iam_role_policy" "read_write" {
  for_each = toset(var.read_write_role_names)

  name   = "${local.bucket_name}-read-write"
  role   = each.value
  policy = data.aws_iam_policy_document.read_write.json
}

resource "aws_iam_role_policy" "read_only" {
  for_each = toset(var.read_only_role_names)

  name   = "${local.bucket_name}-read-only"
  role   = each.value
  policy = data.aws_iam_policy_document.read_only.json
}
