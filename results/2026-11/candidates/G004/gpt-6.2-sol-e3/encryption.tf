data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  key_regions = {
    primary   = var.primary_region
    secondary = var.secondary_region
  }
}

data "aws_iam_policy_document" "key" {
  for_each = local.key_regions
  statement {
    sid       = "EnableAccountIAM"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
  }
  statement {
    sid       = "EncryptThisClustersPostgreSQLLogs"
    actions   = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${each.value}.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${each.value}:${local.account_id}:log-group:/aws/rds/cluster/${local.name}-${each.key}/postgresql"]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "Aurora, PostgreSQL logs, and admin secret for ${local.name} in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key["primary"].json
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora, PostgreSQL logs, and admin secret for ${local.name} in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.key["secondary"].json
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.secondary.key_id
}

ephemeral "random_password" "admin" {
  length           = 40
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
  override_special = "!#$%&*+-_=?:"
}

resource "random_id" "snapshot" {
  byte_length = 4
}

# RDS-managed master credentials aren't supported for Aurora Global Database.
resource "aws_secretsmanager_secret" "admin" {
  name                    = "rds/${local.name}/bootstrap-admin"
  description             = "Privileged Aurora break-glass and bootstrap credential; not for application use."
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string_wo = jsonencode({
    engine   = "postgres"
    username = local.admin_user
    password = ephemeral.random_password.admin.result
    port     = local.port
    dbname   = local.database_name
  })
  secret_string_wo_version = var.admin_credential_version
}

# Read the persisted value instead of using the generator twice. A retry after
# the secret succeeds but cluster creation fails will reuse that same password.
ephemeral "aws_secretsmanager_secret_version" "admin" {
  secret_id  = aws_secretsmanager_secret.admin.id
  version_id = aws_secretsmanager_secret_version.admin.version_id
}
