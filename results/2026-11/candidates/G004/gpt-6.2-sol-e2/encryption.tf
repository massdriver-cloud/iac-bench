data "aws_caller_identity" "current" {}

data "aws_caller_identity" "secondary" {
  provider = aws.secondary
}

locals {
  primary_log_group   = "/aws/rds/cluster/${local.primary_id}/postgresql"
  secondary_log_group = "/aws/rds/cluster/${local.secondary_id}/postgresql"
  regional_key_policies = {
    for region, log_group in { (var.primary_region) = local.primary_log_group, (var.secondary_region) = local.secondary_log_group } : region => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid       = "DelegateKeyPermissionsToAccountIAM"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        },
        {
          Sid       = "EncryptOnlyThisDatabaseLogGroup"
          Effect    = "Allow"
          Principal = { Service = "logs.${region}.amazonaws.com" }
          Action    = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
          Resource  = "*"
          Condition = { ArnEquals = {
            "kms:EncryptionContext:aws:logs:arn" = "arn:aws:logs:${region}:${data.aws_caller_identity.current.account_id}:log-group:${log_group}"
          } }
        }
      ]
    })
  }
}

resource "aws_kms_key" "primary" {
  description             = "Regional key for ${local.primary_id} storage, database logs and bootstrap secret"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.regional_key_policies[var.primary_region]
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Regional key for ${local.secondary_id} storage, database logs and bootstrap secret replica"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = local.regional_key_policies[var.secondary_region]
  lifecycle {
    precondition {
      condition     = data.aws_caller_identity.current.account_id == data.aws_caller_identity.secondary.account_id
      error_message = "The two providers must operate in the same AWS account."
    }
  }
}

resource "aws_cloudwatch_log_group" "primary" {
  name              = local.primary_log_group
  retention_in_days = 90
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider          = aws.secondary
  name              = local.secondary_log_group
  retention_in_days = 90
  kms_key_id        = aws_kms_key.secondary.arn
}

# Aurora Global Database is bootstrapped without relying on RDS-managed master
# credentials. Write-only arguments keep the password out of plans and state.
resource "aws_secretsmanager_secret" "admin" {
  name                    = "aurora/${local.prefix}/bootstrap-admin"
  description             = "Break-glass PostgreSQL administrator for ${local.prefix}; not for workloads"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30

  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}

ephemeral "random_password" "bootstrap" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret_version" "bootstrap" {
  secret_id                = aws_secretsmanager_secret.admin.id
  secret_string_wo         = jsonencode({ username = local.admin_user, password = ephemeral.random_password.bootstrap.result })
  secret_string_wo_version = 1
}

ephemeral "aws_secretsmanager_secret_version" "admin" {
  secret_id     = aws_secretsmanager_secret.admin.id
  version_stage = "AWSCURRENT"
  depends_on    = [aws_secretsmanager_secret_version.bootstrap]
}
