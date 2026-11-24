################################################################################
# RDS Enhanced Monitoring IAM Role (Global IAM Resource)
################################################################################

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  provider = aws.primary

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
  provider = aws.primary
  count    = var.monitoring_interval > 0 ? 1 : 0

  name_prefix        = "${local.name_prefix}-rds-mon-"
  description        = "Allows RDS Enhanced Monitoring to push OS metrics for Aurora ${local.name_prefix}."
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  provider = aws.primary
  count    = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.enhanced_monitoring[0].name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

################################################################################
# Least-Privilege IAM Database Authentication Policy for EKS Service Roles
# Grants rds-db:connect to BOTH primary and secondary cluster resource IDs so
# EKS pods authenticate seamlessly across a regional failover with no IAM edits.
################################################################################

data "aws_iam_policy_document" "db_connect" {
  provider = aws.primary

  statement {
    sid     = "AllowAuroraIAMDBConnectBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = concat(
      [for user in local.db_iam_usernames : "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}"],
      [for user in local.db_iam_usernames : "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"]
    )
  }
}

resource "aws_iam_policy" "db_connect" {
  provider = aws.primary

  name        = "${local.name_prefix}-aurora-db-connect"
  description = "Least-privilege rds-db:connect permissions for ${local.name_prefix} Aurora PostgreSQL Global Database (${var.primary_region} and ${var.secondary_region})."
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "service_db_connect" {
  provider = aws.primary
  for_each = toset(var.service_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
