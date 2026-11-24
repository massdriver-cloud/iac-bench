data "aws_iam_policy_document" "kms" {
  count = local.create_kms_key ? 1 : 0

  statement {
    sid       = "EnableIAMUserPermissions"
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
      sid    = "AllowCloudFrontOAC"
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
        variable = "aws:SourceArn"
        values   = var.cloudfront_distribution_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadOnlyPrincipalsViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.read_only_principals
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.read_write_principals) > 0 ? [1] : []

    content {
      sid    = "AllowReadWritePrincipalsViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
        "kms:ReEncrypt*",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.read_write_principals
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }

  dynamic "statement" {
    for_each = length(var.write_only_principals) > 0 ? [1] : []

    content {
      sid    = "AllowWriteOnlyPrincipalsViaS3"
      effect = "Allow"
      actions = [
        "kms:Decrypt",
        "kms:DescribeKey",
        "kms:Encrypt",
        "kms:GenerateDataKey*",
      ]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.write_only_principals
      }

      condition {
        test     = "StringEquals"
        variable = "kms:ViaService"
        values   = ["s3.${local.region}.${data.aws_partition.current.dns_suffix}"]
      }
    }
  }
}

resource "aws_kms_key" "this" {
  count = local.create_kms_key ? 1 : 0

  description             = "KMS key for S3 bucket ${local.bucket_name} (${var.application}/${var.environment}/${var.purpose})"
  deletion_window_in_days = var.kms_key_deletion_window_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms[0].json
  tags                    = local.common_tags
}

resource "aws_kms_alias" "this" {
  count = local.create_kms_key ? 1 : 0

  name          = "alias/s3/${local.bucket_name}"
  target_key_id = aws_kms_key.this[0].key_id
}
