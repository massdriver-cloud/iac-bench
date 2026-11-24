resource "aws_cloudwatch_log_group" "primary_postgresql" {
  provider          = aws.primary
  name              = "/aws/rds/cluster/${local.name_prefix}-${var.primary_region}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-postgresql-logs"
    Region = var.primary_region
  })
}

resource "aws_cloudwatch_log_group" "primary_iam_auth" {
  provider          = aws.primary
  name              = "/aws/rds/cluster/${local.name_prefix}-${var.primary_region}/iam-db-auth-error"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.primary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.primary_region}-iam-auth-logs"
    Region = var.primary_region
  })
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name_prefix}-${var.secondary_region}/postgresql"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-postgresql-logs"
    Region = var.secondary_region
  })
}

resource "aws_cloudwatch_log_group" "secondary_iam_auth" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.name_prefix}-${var.secondary_region}/iam-db-auth-error"
  retention_in_days = var.cloudwatch_log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn

  tags = merge(local.common_tags, {
    Name   = "${local.name_prefix}-${var.secondary_region}-iam-auth-logs"
    Region = var.secondary_region
  })
}

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  provider = aws.primary

  statement {
    sid     = "AllowRDSEnhancedMonitoringAssumeRole"
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

resource "aws_iam_role" "enhanced_monitoring" {
  provider           = aws.primary
  name               = "${local.name_prefix}-aurora-enhanced-monitoring"
  description        = "IAM role allowing RDS Enhanced Monitoring to publish OS metrics for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-enhanced-monitoring"
  })
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  provider   = aws.primary
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "iam_db_connect" {
  provider = aws.primary

  statement {
    sid    = "AllowAuroraIAMDatabaseAuthentication"
    effect = "Allow"

    actions = [
      "rds-db:connect"
    ]

    resources = flatten([
      for db_user in local.app_db_users : [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}"
      ]
    ])
  }
}

resource "aws_iam_policy" "iam_db_connect" {
  provider    = aws.primary
  name        = "${local.name_prefix}-aurora-db-connect"
  description = "Allows EKS workload IAM roles to authenticate to ${local.name_prefix} Aurora PostgreSQL clusters in ${var.primary_region} and ${var.secondary_region} via IAM database authentication"
  policy      = data.aws_iam_policy_document.iam_db_connect.json

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-aurora-db-connect"
  })
}
