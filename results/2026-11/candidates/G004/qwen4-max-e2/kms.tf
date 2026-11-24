###############################################################################
# Customer-managed KMS keys, one per region. Aurora Global Database requires
# each regional cluster to be encrypted with a key in its own region.
# Rotation on, 30-day deletion window: payment data must not become
# unreadable because of a hasty key deletion.
###############################################################################

data "aws_iam_policy_document" "kms" {
  # Account root admin delegation; RDS/Secrets Manager/Performance Insights
  # obtain use of the key via grants created by the calling IAM principal.
  statement {
    sid       = "EnableAccountAdministration"
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
  provider = aws.primary

  description             = "${local.name} Aurora PostgreSQL (primary region ${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${local.name}-aurora-primary"
  }
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "${local.name} Aurora PostgreSQL (secondary region ${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_in_days
  policy                  = data.aws_iam_policy_document.kms.json

  tags = {
    Name = "${local.name}-aurora-secondary"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
