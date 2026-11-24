###############################################################################
# Customer-managed encryption keys, one per region and independent of each
# other, so losing a region (or its KMS) never affects the other region's
# ability to decrypt. Each key encrypts that region's storage, backups,
# snapshots, Performance Insights data, database logs and the admin secret.
###############################################################################

data "aws_iam_policy_document" "kms" {
  provider = aws.primary

  for_each = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }

  # Access is delegated to IAM in this account; RDS and Secrets Manager use the
  # key through grants created on behalf of authorised callers.
  statement {
    sid       = "AccountIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # CloudWatch Logs may use the key only for this cluster's log groups.
  statement {
    sid = "DatabaseLogGroups"
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]

    principals {
      type        = "Service"
      identifiers = ["logs.${each.value}.amazonaws.com"]
    }

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.current.partition}:logs:${each.value}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.cluster_ids[each.key]}/*",
      ]
    }
  }
}

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Encrypts the ${local.name} database and its secrets in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["primary"].json
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Encrypts the ${local.name} database and its secrets in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["secondary"].json
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.secondary.key_id
}
