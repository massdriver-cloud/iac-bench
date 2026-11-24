data "aws_iam_policy_document" "kms_key" {
  count = var.create_kms_key ? 1 : 0

  statement {
    sid       = "EnableAccountIAMAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowS3ServiceWithinAccount"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["s3.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }

  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid    = "AllowCloudFrontOriginAccessControl"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "ArnLike"
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = var.create_kms_key ? 1 : 0

  description             = "S3 encryption key for ${var.app_name} (${var.purpose}) in ${var.environment}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key[0].json
  tags                    = local.tags
}

resource "aws_kms_alias" "this" {
  count = var.create_kms_key ? 1 : 0

  name          = "alias/s3/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
