data "aws_iam_policy_document" "kms_key_policy" {
  count = local.create_kms_key ? 1 : 0

  # Delegates IAM access management to the owning AWS account and prevents lockout.
  statement {
    sid       = "EnableRootAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # Allows configured CloudFront distributions (via OAC) to decrypt objects.
  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid    = "AllowCloudFrontServicePrincipal"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "Service"
        identifiers = ["cloudfront.amazonaws.com"]
      }

      condition {
        test     = "StringEquals"
        variable = "AWS:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  # Grants decrypt access to explicitly allowed read-only principals (e.g. cross-account roles).
  dynamic "statement" {
    for_each = length(var.allowed_read_only_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipals"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_only_principal_arns
      }
    }
  }

  # Grants encrypt/decrypt access to explicitly allowed read-write principals (e.g. cross-account roles).
  dynamic "statement" {
    for_each = length(var.allowed_read_write_principal_arns) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipals"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.allowed_read_write_principal_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Dedicated KMS key for S3 bucket ${local.bucket_name} (${var.app_name}/${var.environment})"
  deletion_window_in_days = var.kms_key_deletion_window_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key_policy[0].json
  tags                    = local.common_tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
