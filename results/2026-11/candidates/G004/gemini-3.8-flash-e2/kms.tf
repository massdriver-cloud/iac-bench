# Customer Managed KMS Keys (CMK) for customer and payment data encryption at rest

data "aws_iam_policy_document" "kms_primary" {
  statement {
    sid       = "EnableIAMRootPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRDSAndCloudWatch"
    effect = "Allow"
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

    principals {
      type = "Service"
      identifiers = [
        "rds.amazonaws.com",
        "logs.${var.primary_region}.amazonaws.com",
        "secretsmanager.amazonaws.com"
      ]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "KMS CMK for ${var.service_name} Aurora PostgreSQL cluster in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_primary.json
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name_prefix}-rds-${var.primary_region}"
  target_key_id = aws_kms_key.primary.key_id
}

data "aws_iam_policy_document" "kms_secondary" {
  statement {
    sid       = "EnableIAMRootPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRDSAndCloudWatch"
    effect = "Allow"
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

    principals {
      type = "Service"
      identifiers = [
        "rds.amazonaws.com",
        "logs.${var.secondary_region}.amazonaws.com"
      ]
    }
  }
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "KMS CMK for ${var.service_name} Aurora PostgreSQL cluster in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secondary.json
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.name_prefix}-rds-${var.secondary_region}"
  target_key_id = aws_kms_key.secondary.key_id
}
