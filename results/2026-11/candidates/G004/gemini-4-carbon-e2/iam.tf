data "aws_iam_policy_document" "rds_monitoring_assume_role" {
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
      values   = [local.account_id]
    }

    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:${local.partition}:rds:*:${local.account_id}:db:*"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "aurora-${local.name_prefix}-monitoring"
  description        = "RDS Enhanced Monitoring role for ${var.service_name} (${var.environment}) Aurora PostgreSQL instances"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "iam_db_connect" {
  statement {
    sid     = "AllowMultiRegionIAMDatabaseAuthentication"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = concat(
      [
        for db_user in sort(tolist(local.iam_db_users)) :
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}"
      ],
      [
        for db_user in sort(tolist(local.iam_db_users)) :
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}"
      ]
    )
  }
}

resource "aws_iam_policy" "iam_db_connect" {
  name        = "aurora-${local.name_prefix}-db-connect"
  description = "Grants EKS workload IAM roles rds-db:connect to ${var.service_name} (${var.environment}) Aurora PostgreSQL clusters in ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.iam_db_connect.json

  tags = local.common_tags
}

resource "aws_iam_role_policy_attachment" "service_iam_db_connect" {
  for_each = var.service_iam_role_names

  role       = each.value
  policy_arn = aws_iam_policy.iam_db_connect.arn
}
