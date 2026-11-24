# -----------------------------------------------------------------------------
# Dedicated encryption key (skipped when var.kms_key_arn is supplied).
#
# A customer-managed key rather than the S3-managed default gives the owning
# team an independent access control (no key permission = no data, even with
# S3 permissions), a CloudTrail record of key usage, and a kill switch.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  # Standard delegation: access to the key is governed by IAM policies in this
  # account (the module attaches the right ones to the roles you list).
  statement {
    sid       = "EnableIamPolicies"
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
      sid       = "AllowCloudFrontDecrypt"
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

  description             = "Encrypts S3 bucket ${local.bucket_name}"
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
