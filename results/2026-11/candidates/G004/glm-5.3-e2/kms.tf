# Each regional cluster is encrypted with its own customer-managed KMS key.
# KMS keys cannot be shared across regions, and the standby region must be
# able to decrypt its storage without any dependency on the failed region.
# Automatic key rotation is enabled on both keys.

data "aws_iam_policy_document" "kms_key" {
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
}

resource "aws_kms_key" "primary" {
  provider                = aws.primary
  description             = "Aurora PostgreSQL storage encryption for ${local.name} (${var.primary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key.json

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_kms_alias" "primary" {
  provider      = aws.primary
  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora PostgreSQL storage encryption for ${local.name} (${var.secondary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_key.json

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
