data "aws_caller_identity" "primary" {
  provider = aws.primary
}

data "aws_partition" "primary" {
  provider = aws.primary
}

locals {
  default_tags = merge(var.tags, {
    ManagedBy = "OpenTofu"
    Module    = "aurora-postgresql-global"
    Service   = var.name
  })

  primary_cluster_identifier   = "${var.name}-primary"
  secondary_cluster_identifier = "${var.name}-secondary"
  port                         = 5432

  cluster_parameters = {
    "rds.force_ssl"                       = { value = "1", apply_method = "pending-reboot" }
    "shared_preload_libraries"            = { value = "pg_stat_statements", apply_method = "pending-reboot" }
    "password_encryption"                 = { value = "scram-sha-256", apply_method = "immediate" }
    "log_statement"                       = { value = "ddl", apply_method = "immediate" }
    "log_min_duration_statement"          = { value = "1000", apply_method = "immediate" }
    "log_connections"                     = { value = "1", apply_method = "immediate" }
    "log_disconnections"                  = { value = "1", apply_method = "immediate" }
    "log_lock_waits"                      = { value = "1", apply_method = "immediate" }
    "log_temp_files"                      = { value = "0", apply_method = "immediate" }
    "track_io_timing"                     = { value = "1", apply_method = "immediate" }
    "idle_in_transaction_session_timeout" = { value = "300000", apply_method = "immediate" }
  }

  kms_key_policies = {
    for region in [var.primary_region, var.secondary_region] : region => jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Sid    = "EnableAccountAdministration"
          Effect = "Allow"
          Principal = {
            AWS = "arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root"
          }
          Action   = "kms:*"
          Resource = "*"
        },
        {
          Sid    = "AllowRDS"
          Effect = "Allow"
          Principal = {
            Service = "rds.${data.aws_partition.primary.dns_suffix}"
          }
          Action = [
            "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*",
            "kms:ReEncrypt*", "kms:CreateGrant", "kms:ListGrants", "kms:RevokeGrant"
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = data.aws_caller_identity.primary.account_id
            }
          }
        },
        {
          Sid    = "AllowSecretsManager"
          Effect = "Allow"
          Principal = {
            Service = "secretsmanager.${data.aws_partition.primary.dns_suffix}"
          }
          Action = [
            "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"
          ]
          Resource = "*"
          Condition = {
            StringEquals = {
              "aws:SourceAccount" = data.aws_caller_identity.primary.account_id
            }
          }
        },
        {
          Sid    = "AllowCloudWatchLogs"
          Effect = "Allow"
          Principal = {
            Service = "logs.${region}.${data.aws_partition.primary.dns_suffix}"
          }
          Action = [
            "kms:Decrypt", "kms:DescribeKey", "kms:Encrypt", "kms:GenerateDataKey*", "kms:ReEncrypt*"
          ]
          Resource = "*"
          Condition = {
            ArnLike = {
              "kms:EncryptionContext:aws:logs:arn" = "arn:${data.aws_partition.primary.partition}:logs:${region}:${data.aws_caller_identity.primary.account_id}:log-group:/aws/rds/cluster/${var.name}-*"
            }
          }
        }
      ]
    })
  }
}

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "${var.name} Aurora storage, performance insights, logs, and master secret in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = local.kms_key_policies[var.primary_region]

  tags = {
    Name   = "${var.name}-aurora-primary"
    Region = var.primary_region
  }
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${var.name}-aurora-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "${var.name} Aurora storage, performance insights, and logs in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = local.kms_key_policies[var.secondary_region]

  tags = {
    Name   = "${var.name}-aurora-secondary"
    Region = var.secondary_region
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${var.name}-aurora-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.primary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = { Name = "${local.primary_cluster_identifier}-postgresql" }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = { Name = "${local.secondary_cluster_identifier}-postgresql" }
}

resource "aws_rds_cluster_parameter_group" "primary" {
  provider = aws.primary

  name        = "${var.name}-aurora-postgresql-primary"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "Production PostgreSQL controls for ${var.name} in ${var.primary_region}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

resource "aws_rds_cluster_parameter_group" "secondary" {
  provider = aws.secondary

  name        = "${var.name}-aurora-postgresql-secondary"
  family      = "aurora-postgresql${split(".", var.engine_version)[0]}"
  description = "Production PostgreSQL controls for ${var.name} in ${var.secondary_region}"

  dynamic "parameter" {
    for_each = local.cluster_parameters
    content {
      name         = parameter.key
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }
}

resource "aws_rds_global_cluster" "this" {
  provider = aws.primary

  global_cluster_identifier = "${var.name}-global"
  engine                    = "aurora-postgresql"
  engine_version            = var.engine_version
  database_name             = var.database_name
  storage_encrypted         = true
  deletion_protection       = var.deletion_protection
}

resource "aws_rds_cluster" "primary" {
  provider = aws.primary

  cluster_identifier              = local.primary_cluster_identifier
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  engine_mode                     = "provisioned"
  database_name                   = var.database_name
  master_username                 = var.master_username
  manage_master_user_password     = true
  master_user_secret_kms_key_id   = aws_kms_key.primary.arn
  db_subnet_group_name            = aws_db_subnet_group.primary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.primary.name
  vpc_security_group_ids          = [aws_security_group.primary.id]
  port                            = local.port
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.primary.arn

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  backup_retention_period             = var.backup_retention_period
  preferred_backup_window             = var.preferred_backup_window
  preferred_maintenance_window        = var.preferred_maintenance_window
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.primary_cluster_identifier}-final"
  apply_immediately                   = false
  allow_major_version_upgrade         = false

  depends_on = [aws_cloudwatch_log_group.primary]
}

resource "aws_rds_cluster_instance" "primary" {
  provider = aws.primary
  count    = var.primary_instance_count

  identifier                            = "${local.primary_cluster_identifier}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.primary.id
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.primary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = true
  apply_immediately                     = false
  preferred_maintenance_window          = var.preferred_maintenance_window
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.primary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true

  tags = {
    Name = "${local.primary_cluster_identifier}-${count.index + 1}"
    Role = count.index == 0 ? "writer-preferred" : "reader"
  }
}

resource "aws_rds_cluster" "secondary" {
  provider = aws.secondary

  cluster_identifier              = local.secondary_cluster_identifier
  global_cluster_identifier       = aws_rds_global_cluster.this.id
  engine                          = "aurora-postgresql"
  engine_version                  = var.engine_version
  engine_mode                     = "provisioned"
  db_subnet_group_name            = aws_db_subnet_group.secondary.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.secondary.name
  vpc_security_group_ids          = [aws_security_group.secondary.id]
  port                            = local.port
  storage_encrypted               = true
  kms_key_id                      = aws_kms_key.secondary.arn

  iam_database_authentication_enabled = true
  enabled_cloudwatch_logs_exports     = ["postgresql"]
  copy_tags_to_snapshot               = true
  deletion_protection                 = var.deletion_protection
  skip_final_snapshot                 = false
  final_snapshot_identifier           = "${local.secondary_cluster_identifier}-final"
  apply_immediately                   = false
  allow_major_version_upgrade         = false

  # A running primary writer is required before adding the recovery region.
  depends_on = [
    aws_rds_cluster_instance.primary,
    aws_cloudwatch_log_group.secondary,
  ]
}

resource "aws_rds_cluster_instance" "secondary" {
  provider = aws.secondary
  count    = var.secondary_instance_count

  identifier                            = "${local.secondary_cluster_identifier}-${count.index + 1}"
  cluster_identifier                    = aws_rds_cluster.secondary.id
  engine                                = "aurora-postgresql"
  engine_version                        = var.engine_version
  instance_class                        = var.instance_class
  db_subnet_group_name                  = aws_db_subnet_group.secondary.name
  publicly_accessible                   = false
  promotion_tier                        = count.index
  auto_minor_version_upgrade            = true
  apply_immediately                     = false
  preferred_maintenance_window          = var.preferred_maintenance_window
  monitoring_interval                   = 60
  monitoring_role_arn                   = aws_iam_role.rds_monitoring.arn
  performance_insights_enabled          = true
  performance_insights_kms_key_id       = aws_kms_key.secondary.arn
  performance_insights_retention_period = 7
  copy_tags_to_snapshot                 = true

  tags = {
    Name = "${local.secondary_cluster_identifier}-${count.index + 1}"
    Role = "recovery-${count.index + 1}"
  }
}

resource "aws_secretsmanager_secret_rotation" "master" {
  provider = aws.primary

  secret_id          = aws_rds_cluster.primary.master_user_secret[0].secret_arn
  rotate_immediately = false

  rotation_rules {
    automatically_after_days = 30
  }

  depends_on = [aws_rds_cluster_instance.primary]
}
