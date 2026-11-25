# ---------------------------------------------------------------------------
# IAM database authentication: services on EKS assume IAM roles (IRSA) and
# mint short-lived RDS auth tokens instead of holding static passwords.
# This policy is the only permission a service role needs; attach its ARN
# (module output) to the service's IRSA role. It is scoped to this service's
# clusters in both regions and to the declared database users.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "ConnectWithIAM"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      for user in var.iam_database_users :
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}"
    ]
  }

  statement {
    sid     = "ConnectWithIAMAfterFailover"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      for user in var.iam_database_users :
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name}-db-connect"
  description = "rds-db:connect to ${local.name} in ${var.primary_region} and ${var.secondary_region} for the service's IAM roles"
  policy      = data.aws_iam_policy_document.db_connect.json
  tags        = var.tags
}

# ---------------------------------------------------------------------------
# Enhanced Monitoring: OS-level metrics (per-process CPU, memory, filesystem)
# shipped to CloudWatch Logs every 60 seconds. IAM is global, so one role
# serves instances in both regions.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name               = "${local.name}-enhanced-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
