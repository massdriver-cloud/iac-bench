# ---------------------------------------------------------------------------
# IAM: Enhanced Monitoring role (IAM is global, so one role serves both
# regions) and the policy that lets application IAM roles connect to the
# database with IAM authentication instead of passwords.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "monitoring" {
  provider = aws.primary

  name_prefix        = "${substr(local.name, 0, 24)}-rds-mon-"
  description        = "RDS Enhanced Monitoring for Aurora cluster ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  provider = aws.primary

  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Grants rds-db:connect for the configured PostgreSQL roles on both clusters,
# so an application's IRSA role works unchanged after a regional failover.
data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AuroraIamConnect"
    actions = ["rds-db:connect"]
    resources = flatten([
      for user in var.iam_database_usernames : [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  provider = aws.primary

  name        = "${local.name}-aurora-connect"
  description = "Allow IAM database authentication to Aurora cluster ${local.name} (both regions) as: ${join(", ", var.iam_database_usernames)}"
  policy      = data.aws_iam_policy_document.db_connect.json
}
