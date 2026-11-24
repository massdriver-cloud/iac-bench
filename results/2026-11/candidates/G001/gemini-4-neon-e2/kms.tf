data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  # Allow account root (and IAM policies within this account) to administer and delegate KMS access.
  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  # Allow configured read-only principals (including cross-account roles) to decrypt via S3.
  dynamic "statement" {
    for_each = length(var.read_principal_arns) > 0 ? [1] : []

    content {
      sid = "AllowS3ReadPrincipals"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.read_principal_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
    }
  }

  # Allow configured read-write principals (including cross-account roles) to encrypt/decrypt via S3.
  dynamic "statement" {
    for_each = length(var.write_principal_arns) > 0 ? [1] : []

    content {
      sid = "AllowS3WritePrincipals"
      actions = [
        "kms:Encrypt",
        "kms:Decrypt",
        "kms:ReEncrypt*",
        "kms:GenerateDataKey*",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.write_principal_arns
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.amazonaws.com"]
      }
    }
  }

  # Allow authorized CloudFront distributions (OAC) to decrypt KMS-encrypted objects.
  dynamic "statement" {
    for_each = length(var.cloudfront_distribution_arns) > 0 ? [1] : []

    content {
      sid = "AllowCloudFrontOAC"
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
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "Dedicated S3 encryption key for ${local.bucket_name}"
  deletion_window_in_days = local.kms_deletion_window
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = merge(local.common_tags, {
    Name = "s3-${local.bucket_name}"
  })
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3-${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
