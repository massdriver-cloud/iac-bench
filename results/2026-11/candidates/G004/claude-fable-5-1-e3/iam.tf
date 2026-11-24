############################################
# Enhanced Monitoring role (IAM is global; one role serves both regions)
############################################

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
  count = var.monitoring_interval > 0 ? 1 : 0

  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0

  role       = aws_iam_role.monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

############################################
# Application connect policy (IAM database authentication)
#
# Attach this to the EKS pod roles (IRSA / Pod Identity) of the service.
# It covers both regional clusters so nothing about the application's IAM
# needs to change during a failover.
############################################

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AuroraIamConnect"
    actions = ["rds-db:connect"]

    resources = flatten([
      for user in var.iam_database_users : [
        "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name}-aurora-connect"
  description = "Allow IAM database authentication to Aurora ${local.name} in both regions"
  policy      = data.aws_iam_policy_document.db_connect.json
}
