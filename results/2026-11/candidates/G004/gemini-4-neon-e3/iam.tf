# ------------------------------------------------------------------------------
# RDS Enhanced Monitoring IAM Role (global, shared across both regional clusters)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRDSEnhancedMonitoringAssume"
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

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name_prefix}-rds-enhanced-monitoring"
  description        = "IAM role allowing RDS Enhanced Monitoring to publish OS metrics for ${local.name_prefix}"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# ------------------------------------------------------------------------------
# EKS Service IAM Database Authentication Policy (rds-db:connect across both regions)
# ------------------------------------------------------------------------------

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowAuroraIAMAuthBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = concat(
      [for user in local.iam_auth_db_users : "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}"],
      [for user in local.iam_auth_db_users : "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"]
    )
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name_prefix}-aurora-iam-connect"
  description = "Least-privilege IAM database authentication policy (rds-db:connect) for ${local.name_prefix} across ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "service_roles" {
  for_each = toset(var.service_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
