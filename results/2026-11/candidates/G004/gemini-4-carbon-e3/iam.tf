# -----------------------------------------------------------------------------
# RDS Enhanced Monitoring IAM Role (Confused-Deputy Protected)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "enhanced_monitoring_assume_role" {
  count = var.monitoring_interval > 0 ? 1 : 0

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
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  name        = "aurora-${local.name_prefix}-monitoring"
  description = "IAM role allowing RDS Enhanced Monitoring for ${var.service_name} (${var.environment})"

  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume_role[0].json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# IAM Database Authentication Policy (Primary & Secondary Regions)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowAuroraIAMDatabaseConnectPrimaryAndSecondary"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for db_user in local.iam_db_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "aurora-${local.name_prefix}-iam-connect"
  description = "Grants EKS workload IAM roles rds-db:connect to ${var.service_name} (${var.environment}) Aurora clusters in both ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "client_roles" {
  for_each = toset(var.client_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
