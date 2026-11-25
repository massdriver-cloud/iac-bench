resource "aws_kms_key" "primary" {
  description             = "${local.name}: primary Aurora, credentials and performance data"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "${local.name}: secondary Aurora, credentials and performance data"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  lifecycle { prevent_destroy = true }
}

resource "aws_kms_alias" "primary" {
  name          = "alias/${local.name}-database"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.name}-database"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "random_password" "admin" {
  length  = 40
  special = false
}

resource "aws_secretsmanager_secret" "admin" {
  name_prefix             = "${local.name}-bootstrap-"
  description             = "Break-glass/bootstrap credentials; NOT for applications. Rotate using coordinated DB and secret update."
  kms_key_id              = aws_kms_key.primary.arn
  recovery_window_in_days = 30
  replica {
    region     = var.secondary_region
    kms_key_id = aws_kms_key.secondary.arn
  }
  lifecycle { prevent_destroy = true }
}

resource "aws_secretsmanager_secret_version" "admin" {
  secret_id = aws_secretsmanager_secret.admin.id
  secret_string = jsonencode({
    engine   = "postgres"
    username = "platform_admin"
    password = random_password.admin.result
    dbname   = var.database_name
    port     = 5432
  })
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
      values   = ["arn:${data.aws_partition.current.partition}:rds:*:${data.aws_caller_identity.current.account_id}:db:${local.name}-*"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  name_prefix        = "${local.name}-monitor-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "connect" {
  statement {
    sid     = "OnlyApplicationDatabaseUser"
    actions = ["rds-db:connect"]
    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.database_user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.database_user}"
    ]
  }
}

resource "aws_iam_policy" "connect" {
  name_prefix = "${local.name}-connect-"
  description = "IAM database login only; does not grant SQL privileges or secret access"
  policy      = data.aws_iam_policy_document.connect.json
}

resource "aws_iam_role_policy_attachment" "application" {
  for_each   = setunion(var.clients.primary.iam_role_names, var.clients.secondary.iam_role_names)
  role       = each.value
  policy_arn = aws_iam_policy.connect.arn
}
