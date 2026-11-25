###############################################################################
# Encryption at rest
#
# Every object is encrypted with a customer-managed KMS key dedicated to this
# bucket. Compared with the S3-managed default this means reading data needs
# permission on the key as well as the bucket, key usage is audited in
# CloudTrail, and access can be cut off centrally. S3 Bucket Keys are enabled
# so the KMS request cost stays negligible.
###############################################################################

data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  # Standard key policy: the owning account administers the key and delegates
  # usage to IAM policies (such as the ones this module creates).
  statement {
    sid       = "AccountAdministersKeyViaIAM"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid       = "AllowCloudFrontToDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt"]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Encrypts objects in S3 bucket ${local.bucket_name}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = merge(local.tags, { Name = local.bucket_name })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    bucket_key_enabled = true

    apply_server_side_encryption_by_default {
      sse_algorithm     = "aws:kms"
      kms_master_key_id = local.kms_key_arn
    }
  }
}
