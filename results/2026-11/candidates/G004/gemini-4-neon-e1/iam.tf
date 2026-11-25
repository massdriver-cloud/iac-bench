################################################################################
# RDS Enhanced Monitoring IAM Role (Global IAM, Used by Both Regions)
################################################################################

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRdsEnhancedMonitoringAssumeRole"
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

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name_prefix}-rds-monitoring"
  description        = "Least-privilege Enhanced Monitoring role for Aurora PostgreSQL global database ${local.global_cluster_id}"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = {
    Name = "${local.name_prefix}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# Multi-Region IAM Database Authentication Policy for EKS Service IAM Roles
################################################################################

data "aws_iam_policy_document" "db_iam_connect" {
  statement {
    sid     = "AllowIamDatabaseConnectPrimaryAndSecondary"
    effect  = "Allow"
    actions = ["rds-db:connect"]

    resources = concat(
      [
        for user in local.iam_db_users :
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}"
      ],
      [
        for user in local.iam_db_users :
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"
      ]
    )
  }
}

resource "aws_iam_policy" "db_iam_connect" {
  name        = "${local.name_prefix}-rds-iam-connect"
  description = "Grants rds-db:connect for EKS service IAM roles to both primary (${var.primary_region}) and secondary (${var.secondary_region}) Aurora PostgreSQL clusters of ${local.global_cluster_id}"
  policy      = data.aws_iam_policy_document.db_iam_connect.json

  tags = {
    Name = "${local.name_prefix}-rds-iam-connect"
  }
}

resource "aws_iam_role_policy_attachment" "service_iam_connect" {
  for_each = toset(var.service_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_iam_connect.arn
}
