############################################
# Enhanced Monitoring role (IAM is global; one role serves both regions)
############################################

data "aws_iam_policy_document" "monitoring_assume" {
  statement {
    effect  = "Allow"
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

  name_prefix        = "${substr(local.name, 0, 24)}-rds-mon-"
  description        = "RDS Enhanced Monitoring for ${local.name}"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "monitoring" {
  provider = aws.primary

  role       = aws_iam_role.monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

############################################
# Application connect policy — attach to the EKS pod (IRSA / Pod Identity) role
# Grants IAM database authentication as the listed users on BOTH clusters, so the
# same role keeps working after a cross-region failover.
############################################

data "aws_iam_policy_document" "app_connect" {
  statement {
    sid     = "ConnectToAuroraAsApplicationUser"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = flatten([
      for user in var.application_db_users : [
        "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}",
        "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}",
      ]
    ])
  }
}

resource "aws_iam_policy" "app_connect" {
  provider = aws.primary

  name_prefix = "${substr(local.name, 0, 24)}-db-connect-"
  description = "IAM database authentication to ${local.name} Aurora clusters in ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.app_connect.json
}
