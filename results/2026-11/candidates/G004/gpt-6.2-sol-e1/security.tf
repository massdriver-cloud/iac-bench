resource "aws_kms_key" "primary" {
  description             = "Aurora data for ${local.name} in ${var.regions.primary}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora data for ${local.name} in ${var.regions.secondary}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "admin_primary" {
  description             = "Aurora admin secret for ${local.name} in ${var.regions.primary}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_key" "admin_secondary" {
  provider                = aws.secondary
  description             = "Aurora admin secret for ${local.name} in ${var.regions.secondary}"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  tags                    = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_secretsmanager_secret" "admin" {
  name                    = "aurora/${local.name}/admin"
  description             = "Restricted password for the Aurora admin login. Not used by the application."
  kms_key_id              = aws_kms_key.admin_primary.arn
  recovery_window_in_days = 30
  tags                    = local.tags

  replica {
    region     = var.regions.secondary
    kms_key_id = aws_kms_key.admin_secondary.arn
  }

  lifecycle {
    prevent_destroy = true
  }
}

ephemeral "aws_secretsmanager_random_password" "admin" {
  password_length    = 40
  exclude_characters = "@/\" "
}

resource "aws_secretsmanager_secret_version" "bootstrap" {
  secret_id                = aws_secretsmanager_secret.admin.id
  secret_string_wo         = ephemeral.aws_secretsmanager_random_password.admin.random_password
  secret_string_wo_version = 1
  version_stages           = ["AWSCURRENT", "TOFU_BOOTSTRAP"]

  lifecycle {
    prevent_destroy = true
    # Pin the seed version against service GC; don't move AWSCURRENT back after rotation.
    ignore_changes = [version_stages]
  }
}

# Use the saved value so a retry after a partial initial apply uses the same
# password. Normal rotation moves AWSCURRENT out of band against the live writer.
ephemeral "aws_secretsmanager_secret_version" "bootstrap" {
  secret_id     = aws_secretsmanager_secret.admin.id
  version_stage = "AWSCURRENT"
  depends_on    = [aws_secretsmanager_secret_version.bootstrap]
}

data "aws_partition" "current" {}
data "aws_caller_identity" "current" {}

locals {
  database_connect_prefix = "arn:${data.aws_partition.current.partition}:rds-db"
  account_id              = data.aws_caller_identity.current.account_id
  admin_secret_replica_arn = replace(aws_secretsmanager_secret.admin.arn,
  ":secretsmanager:${var.regions.primary}:", ":secretsmanager:${var.regions.secondary}:")
}

data "aws_iam_policy_document" "application" {
  statement {
    sid     = "ConnectAsServiceLogin"
    actions = ["rds-db:connect"]
    resources = [
      "${local.database_connect_prefix}:${var.regions.primary}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.application_db_user}",
      "${local.database_connect_prefix}:${var.regions.secondary}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.application_db_user}",
    ]
  }
}

resource "aws_iam_policy" "application" {
  name        = "${local.name}-aurora-connect"
  description = "Permit only the ${var.application_db_user} PostgreSQL login on the two ${local.name} clusters"
  policy      = data.aws_iam_policy_document.application.json
  tags        = local.tags
}

resource "aws_iam_role_policy_attachment" "application" {
  for_each   = var.application_iam_role_names
  role       = each.key
  policy_arn = aws_iam_policy.application.arn
}
