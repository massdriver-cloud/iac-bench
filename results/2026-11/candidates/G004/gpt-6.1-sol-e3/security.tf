# Separate regional keys avoid making the recovery region depend on a primary-region KMS endpoint.
resource "aws_kms_key" "primary" {
  description             = "${local.prefix} database, backups, logs and bootstrap secret"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}
resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} DR database, backups, logs and bootstrap secret"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.kms.json
}
data "aws_iam_policy_document" "kms" {
  statement {
    sid       = "EnableAccountIAMPolicies"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    sid       = "EncryptedRDSLogs"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["logs.${var.primary_region}.amazonaws.com", "logs.${var.secondary_region}.amazonaws.com"]
    }
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.current.partition}:logs:${var.primary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.prefix}-primary/*",
        "arn:${data.aws_partition.current.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/rds/cluster/${local.prefix}-secondary/*"
      ]
    }
  }
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

# Global databases use an explicitly managed bootstrap credential, not application passwords.
# This value is sensitive, but IS stored in OpenTofu state: secure the backend accordingly.
resource "random_password" "master" {
  length  = 40
  special = false
}
resource "aws_secretsmanager_secret" "bootstrap" {
  name_prefix             = "${local.prefix}-bootstrap-"
  description             = "Break-glass/SQL bootstrap only. Applications use IAM auth. Rotate through a coordinated database+secret procedure."
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
}
resource "aws_secretsmanager_secret_version" "bootstrap" {
  secret_id = aws_secretsmanager_secret.bootstrap.id
  secret_string = jsonencode({
    username = "cluster_admin"
    password = random_password.master.result
    engine   = "postgres"
    dbname   = var.database_name
    port     = 5432
  })
}

data "aws_iam_policy_document" "connect" {
  statement {
    actions = ["rds-db:connect"]
    resources = flatten([for user in var.database_users : [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"
    ]])
  }
}
resource "aws_iam_policy" "connect" {
  name_prefix = "${local.prefix}-db-connect-"
  description = "IAM PostgreSQL logins in both regions, including after regional promotion"
  policy      = data.aws_iam_policy_document.connect.json
}
resource "aws_iam_role_policy_attachment" "applications" {
  for_each   = var.application_role_names
  role       = each.value
  policy_arn = aws_iam_policy.connect.arn
}

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values = [
        "arn:${data.aws_partition.current.partition}:rds:${var.primary_region}:${data.aws_caller_identity.current.account_id}:db:${local.prefix}-primary-*",
        "arn:${data.aws_partition.current.partition}:rds:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:db:${local.prefix}-secondary-*"
      ]
    }
  }
}
resource "aws_iam_role" "monitoring" {
  name_prefix        = "${local.prefix}-monitor-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}
resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
