data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid    = "EnableAccountRootAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRDSAndSecretsManagerViaService"
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
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "rds.${var.primary_region}.amazonaws.com",
        "secretsmanager.${var.primary_region}.amazonaws.com",
        "pi.${var.primary_region}.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsForClusterLogGroups"
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
      "kms:Describe*",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.primary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_id}/*"
      ]
    }
  }
}

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid    = "EnableAccountRootAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRDSAndSecretsManagerViaService"
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
      "kms:DescribeKey",
    ]

    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [local.account_id]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values = [
        "rds.${var.secondary_region}.amazonaws.com",
        "secretsmanager.${var.secondary_region}.amazonaws.com",
        "pi.${var.secondary_region}.amazonaws.com",
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchLogsForClusterLogGroups"
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
      "kms:Describe*",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.secondary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_id}/*"
      ]
    }
  }
}

resource "aws_kms_key" "primary" {
  region                  = var.primary_region
  description             = "Multi-region KMS key for ${var.service_name} (${var.environment}) Aurora PostgreSQL storage, secrets, PI, and audit logs"
  enable_key_rotation     = true
  multi_region            = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = merge(local.common_tags, {
    Name = "aurora-${local.name_prefix}-${var.primary_region}"
  })
}

resource "aws_kms_alias" "primary" {
  region        = var.primary_region
  name          = "alias/aurora-${local.name_prefix}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_replica_key" "secondary" {
  region                  = var.secondary_region
  description             = "Multi-region KMS replica key for ${var.service_name} (${var.environment}) Aurora PostgreSQL in ${var.secondary_region}"
  primary_key_arn         = aws_kms_key.primary.arn
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = merge(local.common_tags, {
    Name = "aurora-${local.name_prefix}-${var.secondary_region}"
  })
}

resource "aws_kms_alias" "secondary" {
  region        = var.secondary_region
  name          = "alias/aurora-${local.name_prefix}"
  target_key_id = aws_kms_replica_key.secondary.key_id
}
