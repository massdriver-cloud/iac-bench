################################################################################
# Primary Region Customer Managed KMS Key (Storage, Secrets, PI, Logs, Alerts)
################################################################################

data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
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
      "kms:Describe*"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_id}/*"]
    }
  }

  statement {
    sid    = "AllowCloudWatchAndRdsEventSnsEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*"
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com",
        "sns.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Regional CMK for Aurora PostgreSQL cluster ${local.primary_cluster_id} (storage, master secret, Performance Insights, logs, alerts)"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = {
    Name = "${local.primary_cluster_id}-kms"
    Role = "primary"
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/aurora/${local.primary_cluster_id}"
  target_key_id = aws_kms_key.primary.key_id
}

################################################################################
# Secondary Region Customer Managed KMS Key (Independent Regional Encryption)
################################################################################

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid       = "EnableAccountRootAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
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
      "kms:Describe*"
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_id}/*"]
    }
  }

  statement {
    sid    = "AllowCloudWatchAndRdsEventSnsEncryption"
    effect = "Allow"
    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*"
    ]
    resources = ["*"]

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "rds.amazonaws.com",
        "sns.amazonaws.com"
      ]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Regional CMK for Aurora PostgreSQL cluster ${local.secondary_cluster_id} (storage, Performance Insights, logs, alerts)"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = {
    Name = "${local.secondary_cluster_id}-kms"
    Role = "secondary"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/aurora/${local.secondary_cluster_id}"
  target_key_id = aws_kms_key.secondary.key_id
}
