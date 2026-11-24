# -----------------------------------------------------------------------------
# Customer-Managed KMS Keys (Primary & Secondary Regions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_primary" {
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

  statement {
    sid    = "AllowRDSAndSecretsManagerViaService"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ListGrants",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

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

  statement {
    sid    = "AllowCloudWatchLogsAuditEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt*",
      "kms:Describe*",
      "kms:Encrypt*",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.primary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_id}/*",
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchAlarmsAndRDSEventsToSNS"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "primary" {
  region                  = var.primary_region
  description             = "Customer-managed key encrypting ${var.service_name} (${local.env_short}) Aurora storage, secrets, logs, and alerts in ${var.primary_region}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = merge(local.tags, {
    Name = "${local.primary_cluster_id}-kms"
  })
}

resource "aws_kms_alias" "primary" {
  region        = var.primary_region
  name          = "alias/aurora/${local.primary_cluster_id}"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
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

  statement {
    sid    = "AllowRDSAndSecretsManagerViaService"
    effect = "Allow"
    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ListGrants",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

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

  statement {
    sid    = "AllowCloudWatchLogsAuditEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt*",
      "kms:Describe*",
      "kms:Encrypt*",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${local.partition}:logs:${var.secondary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_id}/*",
      ]
    }
  }

  statement {
    sid    = "AllowCloudWatchAlarmsAndRDSEventsToSNS"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_kms_key" "secondary" {
  region                  = var.secondary_region
  description             = "Customer-managed key encrypting ${var.service_name} (${local.env_short}) Aurora storage, secrets, logs, and alerts in ${var.secondary_region}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = merge(local.tags, {
    Name = "${local.secondary_cluster_id}-kms"
  })
}

resource "aws_kms_alias" "secondary" {
  region        = var.secondary_region
  name          = "alias/aurora/${local.secondary_cluster_id}"
  target_key_id = aws_kms_key.secondary.key_id
}
