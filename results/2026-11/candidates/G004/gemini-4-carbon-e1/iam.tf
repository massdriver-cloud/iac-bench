# -----------------------------------------------------------------------------
# RDS Enhanced Monitoring IAM Role (Confused-Deputy Scoped)
# -----------------------------------------------------------------------------

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

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name_prefix}-rds-monitoring"
  description        = "Allows RDS Enhanced Monitoring to publish OS-level metrics for ${var.service_name} (${local.env_short})"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# Multi-Region EKS IAM Database Authentication Policies (rds-db:connect)
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowAuroraIAMConnectBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for user in local.db_iam_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name_prefix}-aurora-iam-connect"
  description = "Grants EKS workload IAM roles short-lived IAM token authentication to ${var.service_name} (${local.env_short}) Aurora clusters in both ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "service_db_connect" {
  for_each = {
    for r in var.service_iam_roles : r => reverse(split("/", r))[0]
  }

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}

data "aws_iam_policy_document" "db_connect_readonly" {
  statement {
    sid     = "AllowAuroraReadOnlyIAMConnectBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for user in local.db_readonly_iam_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect_readonly" {
  name        = "${local.name_prefix}-aurora-iam-connect-ro"
  description = "Grants read-only IAM token authentication to ${var.service_name} (${local.env_short}) Aurora clusters in both ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect_readonly.json

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "readonly_db_connect" {
  for_each = {
    for r in var.readonly_iam_roles : r => reverse(split("/", r))[0]
  }

  role       = each.value
  policy_arn = aws_iam_policy.db_connect_readonly.arn
}
