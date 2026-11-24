data "aws_iam_policy_document" "kms" {
  for_each = { primary = var.primary_region, secondary = var.secondary_region }
  statement {
    sid       = "AccountAdministration"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "EncryptedDatabaseLogs"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${each.value}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${data.aws_partition.current.partition}:logs:${each.value}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.prefix}-*"]
    }
  }
  statement {
    sid       = "CloudWatchAlarmNotifications"
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_kms_key" "primary" {
  description             = "${local.prefix} primary database, backups, logs and administrator secret"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["primary"].json
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} independent DR database, backups, logs and secret replica key"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms["secondary"].json
  lifecycle { prevent_destroy = true }
}
resource "aws_kms_alias" "primary" {
  name          = "alias/${local.prefix}-database"
  target_key_id = aws_kms_key.primary.key_id
}
resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.prefix}-database"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "random_password" "administrator" {
  length  = 40
  special = false
}
resource "random_id" "snapshot" { byte_length = 4 }

# Explicit secret storage works with Aurora Global Database. No application gets this secret.
# This password also exists in OpenTofu state: protect the backend as a production secret store.
resource "aws_secretsmanager_secret" "administrator" {
  name_prefix             = "${local.prefix}-break-glass-"
  description             = "Break-glass administrator only; applications use IAM database authentication"
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
  lifecycle { prevent_destroy = true }
}
resource "aws_secretsmanager_secret_version" "administrator" {
  secret_id = aws_secretsmanager_secret.administrator.id
  secret_string = jsonencode({
    username = "dbadmin", password = random_password.administrator.result,
    engine   = "postgres", dbname = var.database_name, port = 5432
  })
}

resource "aws_iam_role" "monitoring" {
  name = "${local.prefix}-rds-monitor"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow", Action = "sts:AssumeRole",
      Principal = { Service = "monitoring.rds.amazonaws.com" },
      Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.current.account_id } }
    }]
  })
}
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_iam_policy" "application" {
  name_prefix = "${local.prefix}-db-connect-"
  description = "Only IAM authentication as ${var.application_db_user}, in either global database region"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow", Action = "rds-db:connect",
      Resource = [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.application_db_user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.application_db_user}"
      ]
    }]
  })
}
resource "aws_iam_role_policy_attachment" "application" {
  for_each   = var.application_iam_role_names
  role       = each.value
  policy_arn = aws_iam_policy.application.arn
}
