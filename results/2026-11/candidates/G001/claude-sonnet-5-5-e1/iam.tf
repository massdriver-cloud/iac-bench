locals {
  kms_arns = var.kms_key_arn == null ? [] : [var.kms_key_arn]
}

data "aws_iam_policy_document" "app_read" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.this.arn]
  }

  statement {
    actions   = ["s3:GetObject", "s3:GetObjectVersion"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  dynamic "statement" {
    for_each = local.kms_arns
    content {
      sid       = "KmsDecrypt"
      actions   = ["kms:Decrypt"]
      resources = [statement.value]
    }
  }
}

data "aws_iam_policy_document" "app_access" {
  source_policy_documents = [data.aws_iam_policy_document.app_read.json]

  statement {
    sid       = "WriteObjects"
    actions   = ["s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.this.arn}/*"]
  }

  statement {
    sid       = "ListUploads"
    actions   = ["s3:ListBucketMultipartUploads"]
    resources = [aws_s3_bucket.this.arn]
  }

  dynamic "statement" {
    for_each = local.kms_arns
    content {
      sid       = "KmsEncrypt"
      actions   = ["kms:GenerateDataKey", "kms:Encrypt"]
      resources = [statement.value]
    }
  }
}
