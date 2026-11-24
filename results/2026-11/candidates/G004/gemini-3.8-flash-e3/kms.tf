data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRDS"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRDS"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowSecretsManager"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogs"
    effect = "Allow"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "primary" {
  count                   = var.primary_kms_key_arn == null ? 1 : 0
  description             = "KMS Customer Managed Key for Aurora PostgreSQL ${var.name} (primary region)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-aurora-kms-primary"
      Region = var.primary_region
    }
  )
}

resource "aws_kms_alias" "primary" {
  count         = var.primary_kms_key_arn == null ? 1 : 0
  name          = "alias/${var.name}-aurora-primary"
  target_key_id = aws_kms_key.primary[0].key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  count                   = var.secondary_kms_key_arn == null ? 1 : 0
  description             = "KMS Customer Managed Key for Aurora PostgreSQL ${var.name} (secondary region)"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = merge(
    local.common_tags,
    {
      Name   = "${var.name}-aurora-kms-secondary"
      Region = var.secondary_region
    }
  )
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  count         = var.secondary_kms_key_arn == null ? 1 : 0
  name          = "alias/${var.name}-aurora-secondary"
  target_key_id = aws_kms_key.secondary[0].key_id
}
