# One customer-managed key per region. Each key encrypts everything this
# database keeps in its region: cluster storage (and therefore backups and
# snapshots), Performance Insights data, PostgreSQL logs and the master
# credential secret. The keys are independent, so neither region relies on the
# other to read its own data.

data "aws_iam_policy_document" "kms" {
  for_each = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }

  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }

  statement {
    sid = "CloudWatchLogsForThisDatabase"
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
      values   = ["arn:${local.partition}:logs:${each.value}:${local.account_id}:log-group:/aws/rds/cluster/${local.cluster_identifiers[each.key]}/*"]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora PostgreSQL ${local.name} data at rest in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["primary"].json
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL ${local.name} data at rest in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["secondary"].json
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
