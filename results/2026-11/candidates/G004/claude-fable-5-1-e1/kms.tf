############################################
# Customer-managed KMS keys — one per region (Aurora Global requires a key in each)
# Encrypts storage, snapshots, Performance Insights and the master-user secret.
############################################

data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "AccountAdministration"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  statement {
    sid    = "AllowRDSAndSecretsManagerUse"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
      "kms:CreateGrant",
      "kms:ListGrants",
      "kms:RevokeGrant",
    ]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }

    condition {
      test     = "StringLike"
      variable = "kms:ViaService"
      values   = ["rds.*.amazonaws.com", "secretsmanager.*.amazonaws.com"]
    }
  }
}

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Aurora PostgreSQL ${local.name} (${var.primary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = { Name = "${local.primary_cluster_id}-db" }
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.primary_cluster_id}-db"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL ${local.name} (${var.secondary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms.json

  tags = { Name = "${local.secondary_cluster_id}-db" }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.secondary_cluster_id}-db"
  target_key_id = aws_kms_key.secondary.key_id
}
