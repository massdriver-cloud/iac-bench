# ---------------------------------------------------------------------------
# Encryption keys. Aurora requires a KMS key in the cluster's own region, so
# the module creates one customer-managed key per region. Customer-managed
# keys (rather than the AWS-managed default) give the platform team control,
# rotation and audit over the encryption of customer/payment data.
# ---------------------------------------------------------------------------

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
  description         = "Aurora PostgreSQL storage encryption for ${local.name_env} (${var.primary_region})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name_env}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.dr

  description         = "Aurora PostgreSQL storage encryption for ${local.secondary_cluster_id} (${var.secondary_region})."
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms.json
}

resource "aws_kms_alias" "secondary" {
  provider = aws.dr

  name          = "alias/${local.name_env}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
