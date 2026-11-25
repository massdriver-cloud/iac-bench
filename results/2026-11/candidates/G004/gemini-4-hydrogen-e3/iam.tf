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
      values   = [local.account_id]
    }
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name_prefix}-rds-monitoring"
  description        = "Allows RDS Enhanced Monitoring to publish OS metrics to CloudWatch for ${local.name_prefix}."
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json

  tags = {
    Name = "${local.name_prefix}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowIAMDatabaseConnectBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for db_user in local.iam_database_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name_prefix}-aurora-iam-connect"
  description = "Grants EKS workloads IAM database authentication (rds-db:connect) to ${local.name_prefix} in both regions."
  policy      = data.aws_iam_policy_document.db_connect.json

  tags = {
    Name = "${local.name_prefix}-aurora-iam-connect"
  }
}

resource "aws_iam_role_policy_attachment" "eks_db_connect" {
  for_each = toset(var.eks_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
