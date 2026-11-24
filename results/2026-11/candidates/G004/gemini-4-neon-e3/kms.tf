# ------------------------------------------------------------------------------
# Primary Region Customer-Managed KMS Key
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid    = "EnableIAMUserPermissions"
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
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.primary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_id}/*"]
    }
  }

  statement {
    sid    = "AllowCloudWatchAndRDSToPublishToEncryptedSNS"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "primary" {
  description             = "Customer-managed KMS key for primary Aurora PostgreSQL cluster ${local.primary_cluster_id}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json

  tags = {
    Name = "${local.primary_cluster_id}-kms"
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.primary_cluster_id}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

# ------------------------------------------------------------------------------
# Secondary Region Customer-Managed KMS Key
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "kms_secondary" {
  provider = aws.secondary

  statement {
    sid    = "EnableIAMUserPermissions"
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
      "kms:Describe*"
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${var.secondary_region}:${local.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_id}/*"]
    }
  }

  statement {
    sid    = "AllowCloudWatchAndRDSToPublishToEncryptedSNS"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "cloudwatch.amazonaws.com",
        "events.amazonaws.com",
        "rds.amazonaws.com"
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*"
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Customer-managed KMS key for secondary Aurora PostgreSQL cluster ${local.secondary_cluster_id}"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json

  tags = {
    Name = "${local.secondary_cluster_id}-kms"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.secondary_cluster_id}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
