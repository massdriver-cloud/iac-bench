# Customer-managed keys rather than the AWS-owned default: these databases hold
# customer and payment data, so we want annual rotation, CloudTrail visibility
# and the ability to revoke access. One key per region; each encrypts that
# region's cluster storage and credentials secret.
data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "EnableRootAccountFullAccess"
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
  description             = "CMK for ${local.prefix} Aurora storage and secrets (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${local.prefix}-rds"
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.prefix}-rds"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "CMK for ${local.prefix} Aurora storage and secrets (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${local.prefix}-rds"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.prefix}-rds"
  target_key_id = aws_kms_key.secondary.key_id
}
