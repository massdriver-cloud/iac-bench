# -----------------------------------------------------------------------------
# Primary Region Customer-Managed KMS Key
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "primary_kms" {
  count = local.create_primary_kms_key ? 1 : 0

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
      "kms:Describe*",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.primary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_id}/*",
      ]
    }
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
      ]
    }
  }
}

resource "aws_kms_key" "primary" {
  count = local.create_primary_kms_key ? 1 : 0

  region                  = var.primary_region
  description             = "Aurora PostgreSQL CMK for ${var.service_name} (${var.environment}) in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.primary_kms[0].json

  tags = merge(local.tags, {
    Name   = "${local.primary_cluster_id}-kms"
    region = var.primary_region
  })
}

resource "aws_kms_alias" "primary" {
  count = local.create_primary_kms_key ? 1 : 0

  region        = var.primary_region
  name          = "alias/aurora/${var.environment}/${var.service_name}"
  target_key_id = aws_kms_key.primary[0].key_id
}

# -----------------------------------------------------------------------------
# Secondary Region Customer-Managed KMS Key
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "secondary_kms" {
  count = local.create_secondary_kms_key ? 1 : 0

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
      "kms:Describe*",
    ]

    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.secondary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_id}/*",
      ]
    }
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
      ]
    }
  }
}

resource "aws_kms_key" "secondary" {
  count = local.create_secondary_kms_key ? 1 : 0

  region                  = var.secondary_region
  description             = "Aurora PostgreSQL CMK for ${var.service_name} (${var.environment}) in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.secondary_kms[0].json

  tags = merge(local.tags, {
    Name   = "${local.secondary_cluster_id}-kms"
    region = var.secondary_region
  })
}

resource "aws_kms_alias" "secondary" {
  count = local.create_secondary_kms_key ? 1 : 0

  region        = var.secondary_region
  name          = "alias/aurora/${var.environment}/${var.service_name}"
  target_key_id = aws_kms_key.secondary[0].key_id
}
