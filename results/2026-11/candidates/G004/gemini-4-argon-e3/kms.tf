data "aws_iam_policy_document" "kms_primary" {
  provider = aws.primary

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRDSAndSecretsManagerEncryption"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "rds.${var.primary_region}.amazonaws.com",
        "secretsmanager.${var.primary_region}.amazonaws.com"
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.name_prefix}-${var.primary_region}/*"]
    }
  }
}

resource "aws_kms_key" "primary" {
  provider                = aws.primary
  description             = "Customer-managed KMS key for ${local.name_prefix} Aurora PostgreSQL cluster, PI, Secrets Manager, and CloudWatch Logs in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-aurora-kms"
    Region = var.primary_region
  })
}

resource "aws_kms_alias" "primary" {
  provider      = aws.primary
  name          = "alias/aurora/${local.name_prefix}/${var.primary_region}"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
  provider = aws.secondary

  statement {
    sid    = "EnableRootAccountPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRDSAndSecretsManagerEncryption"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:DescribeKey"
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values = [
        "rds.${var.secondary_region}.amazonaws.com",
        "secretsmanager.${var.secondary_region}.amazonaws.com"
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsEncryption"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*"
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.name_prefix}-${var.secondary_region}/*"]
    }
  }
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Customer-managed KMS key for ${local.name_prefix} Aurora PostgreSQL cluster, PI, Secrets Manager, and CloudWatch Logs in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-aurora-kms"
    Region = var.secondary_region
  })
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/aurora/${local.name_prefix}/${var.secondary_region}"
  target_key_id = aws_kms_key.secondary.key_id
}
