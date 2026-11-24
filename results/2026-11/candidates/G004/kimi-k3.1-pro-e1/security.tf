data "aws_iam_policy_document" "regional_key" {
  statement {
    sid    = "EnableAccountAdministration"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.primary.partition}:iam::${data.aws_caller_identity.primary.account_id}:root"]
    }

    actions   = ["kms:*"]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRDSKeyUseAndGrants"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["rds.amazonaws.com"]
    }

    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ListGrants",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "kms:CallerAccount"
      values   = [data.aws_caller_identity.primary.account_id]
    }
  }

  statement {
    sid    = "AllowRDSSecretsIntegration"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["secretsmanager.amazonaws.com"]
    }

    actions = [
      "kms:CreateGrant",
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AllowRegionalCloudWatchLogs"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "logs.${var.primary_region}.amazonaws.com",
        "logs.${var.secondary_region}.amazonaws.com",
      ]
    }

    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*",
    ]
    resources = ["*"]

    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values = [
        "arn:${data.aws_partition.primary.partition}:logs:${var.primary_region}:${data.aws_caller_identity.primary.account_id}:*",
        "arn:${data.aws_partition.primary.partition}:logs:${var.secondary_region}:${data.aws_caller_identity.primary.account_id}:*",
      ]
    }
  }

  statement {
    sid    = "AllowEncryptedOperationsNotifications"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "sns.amazonaws.com"]
    }

    actions = [
      "kms:Decrypt",
      "kms:GenerateDataKey*",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "${local.base_name} Aurora, secrets, logs, and alarms in ${var.primary_region}"
  policy                  = data.aws_iam_policy_document.regional_key.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.base_name}-aurora-primary"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "${local.base_name} Aurora, logs, and alarms in ${var.secondary_region}"
  policy                  = data.aws_iam_policy_document.regional_key.json
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.base_name}-aurora-secondary"
  target_key_id = aws_kms_key.secondary.key_id
}

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.base_name}-primary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.base_name}-secondary/postgresql"
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}

resource "aws_iam_role" "enhanced_monitoring" {
  provider = aws.primary

  name = "${local.base_name}-rds-monitoring"
  path = "/service-roles/"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "AllowRDSEnhancedMonitoring"
      Effect = "Allow"
      Principal = {
        Service = "monitoring.rds.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  provider = aws.primary

  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.primary.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "application_connect" {
  statement {
    sid    = "ConnectWithIAMToEitherGlobalClusterMember"
    effect = "Allow"
    actions = [
      "rds-db:connect",
    ]
    resources = [
      "arn:${data.aws_partition.primary.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.primary.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.iam_database_user_name}",
      "arn:${data.aws_partition.primary.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.secondary.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.iam_database_user_name}",
    ]
  }
}

resource "aws_iam_policy" "application_connect" {
  provider = aws.primary

  name        = "${local.base_name}-aurora-iam-connect"
  description = "IAM database authentication to either regional member of ${aws_rds_global_cluster.this.id}"
  policy      = data.aws_iam_policy_document.application_connect.json
}

resource "aws_iam_role_policy_attachment" "application_connect" {
  provider = aws.primary
  for_each = toset(var.application_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.application_connect.arn
}
