# ---------------------------------------------------------------------------
# Service access: IAM database authentication
# ---------------------------------------------------------------------------
# Services already reach AWS through IAM roles, so they log in to PostgreSQL
# the same way: a short-lived token signed by the pod's role instead of a
# stored password. The policy covers both regional clusters, so a service keeps
# working after a failover without any IAM change.

data "aws_iam_policy_document" "connect" {
  statement {
    sid     = "ConnectAsApplicationUsers"
    actions = ["rds-db:connect"]

    resources = flatten([
      for user in var.app_database_users : [
        "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "connect" {
  count = length(var.app_database_users) > 0 ? 1 : 0

  name        = "${local.name}-aurora-connect"
  description = "Connect to the ${local.name} Aurora PostgreSQL database, in either region, as: ${join(", ", var.app_database_users)}"
  policy      = data.aws_iam_policy_document.connect.json
}

resource "aws_iam_role_policy_attachment" "connect" {
  for_each = length(var.app_database_users) > 0 ? toset(var.app_role_names) : toset([])

  role       = each.value
  policy_arn = aws_iam_policy.connect[0].arn
}

# ---------------------------------------------------------------------------
# Enhanced Monitoring (OS-level metrics for every instance, both regions)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
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

resource "aws_iam_role" "monitoring" {
  name               = "${local.name}-aurora-monitoring"
  description        = "Lets RDS publish Enhanced Monitoring metrics for ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${local.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
