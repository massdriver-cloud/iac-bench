###############################################################################
# Database access for services: IAM database authentication.
#
# Pods already have IAM roles. Instead of handing them a long-lived password,
# their role is allowed to request a 15-minute login token for specific
# PostgreSQL users, in either region. Nothing to store, rotate or leak.
###############################################################################

data "aws_iam_policy_document" "connect" {
  provider = aws.primary

  statement {
    sid     = "ConnectWithIAMToken"
    actions = ["rds-db:connect"]

    resources = flatten([
      for user in local.iam_database_users : [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "connect" {
  provider = aws.primary

  name        = "${local.name}-db-connect"
  description = "Connect to the ${local.name} Aurora database in either region as: ${join(", ", local.iam_database_users)}"
  policy      = data.aws_iam_policy_document.connect.json
}

resource "aws_iam_role_policy_attachment" "connect" {
  provider = aws.primary
  for_each = toset(var.iam_auth_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.connect.arn
}

###############################################################################
# Role RDS uses to publish OS-level (enhanced monitoring) metrics. IAM is
# global, so one role serves both regions.
###############################################################################

data "aws_iam_policy_document" "monitoring_assume" {
  provider = aws.primary

  statement {
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

resource "aws_iam_role" "monitoring" {
  provider = aws.primary

  name               = "${local.name}-rds-monitoring"
  description        = "Lets RDS enhanced monitoring publish OS metrics for ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  provider = aws.primary

  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
