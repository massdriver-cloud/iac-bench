# Separate regional keys are intentional: Aurora re-encrypts the replicated
# storage for the secondary Region and neither Region depends on the other's KMS
# endpoint during recovery.
data "aws_iam_policy_document" "primary_kms" {
  statement {
    sid    = "EnableAccountIAMPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRegionalCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.${data.aws_partition.primary.dns_suffix}"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.primary.partition}:logs:${var.primary_region}:${data.aws_caller_identity.primary.account_id}:log-group:/aws/rds/cluster/${local.primary_cluster_identifier}/*",
      ]
    }
  }
}

data "aws_iam_policy_document" "secondary_kms" {
  provider = aws.secondary

  statement {
    sid    = "EnableAccountIAMPermissions"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.secondary.partition}:iam::${data.aws_caller_identity.secondary.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRegionalCloudWatchLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logs.${var.secondary_region}.${data.aws_partition.secondary.dns_suffix}"]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.secondary.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.secondary.account_id}:log-group:/aws/rds/cluster/${local.secondary_cluster_identifier}/*",
      ]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora storage, Performance Insights, secrets, and logs for ${var.name} in ${var.primary_region}"
  policy                  = data.aws_iam_policy_document.primary_kms.json
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name}-aurora-primary"
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora storage, Performance Insights, and logs for ${var.name} in ${var.secondary_region}"
  policy                  = data.aws_iam_policy_document.secondary_kms.json
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${var.name}-aurora-secondary"
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${var.name}-aurora-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${var.name}-aurora-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}
