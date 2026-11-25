data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    sid     = "AllowRDSMonitoringAssumeRole"
    effect  = "Allow"
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
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name_prefix        = "${local.name_prefix}-rds-mon-"
  description        = "IAM role for RDS Enhanced Monitoring on ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowAuroraIAMAuthPrimary"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      for db_user in local.iam_auth_db_users :
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}"
    ]
  }

  statement {
    sid     = "AllowAuroraIAMAuthSecondary"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      for db_user in local.iam_auth_db_users :
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}"
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  name_prefix = "${local.name_prefix}-db-connect-"
  description = "Grants EKS service IAM roles rds-db:connect access to ${local.name_prefix} Aurora PostgreSQL in primary and secondary regions"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "eks_db_connect" {
  for_each = toset(var.eks_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}

data "aws_iam_policy_document" "master_secret_read" {
  statement {
    sid       = "AllowReadMasterSecret"
    effect    = "Allow"
    actions   = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"]
    resources = [aws_rds_cluster.primary.master_user_secret[0].secret_arn]
  }

  statement {
    sid       = "AllowDecryptMasterSecretViaSecretsManager"
    effect    = "Allow"
    actions   = ["kms:Decrypt"]
    resources = [aws_kms_key.primary.arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["secretsmanager.${var.primary_region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "master_secret_read" {
  name_prefix = "${local.name_prefix}-admin-secret-"
  description = "Least-privilege read access to the RDS-managed master credentials secret for schema migrations and break-glass administration on ${local.name_prefix}"
  policy      = data.aws_iam_policy_document.master_secret_read.json
}
