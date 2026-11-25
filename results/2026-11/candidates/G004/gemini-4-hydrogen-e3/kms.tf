data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid       = "AllowRootAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.primary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.name_prefix}-primary/*"]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Customer-managed KMS key for ${local.name_prefix} Aurora PostgreSQL primary region encryption."
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = {
    Name = "${local.name_prefix}-primary-rds-kms"
    Role = "primary"
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid       = "AllowRootAccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.secondary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.name_prefix}-secondary/*"]
    }
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Customer-managed KMS key for ${local.name_prefix} Aurora PostgreSQL secondary region encryption."
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = {
    Name = "${local.name_prefix}-secondary-rds-kms"
    Role = "secondary"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.name_prefix}-rds"
  target_key_id = aws_kms_key.secondary.key_id
}
