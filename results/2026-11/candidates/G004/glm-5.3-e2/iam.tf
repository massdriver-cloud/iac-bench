# -----------------------------------------------------------------------------
# Enhanced monitoring. RDS instances push OS-level metrics to CloudWatch under a
# service role; IAM roles are global, so one role serves both regions.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRDSToAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  count              = var.monitoring_interval > 0 ? 1 : 0
  name               = "${local.name}-rds-monitoring"
  description        = "Service role used by RDS to publish enhanced monitoring metrics for the ${var.name} (${var.environment}) database."
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = {
    Name = "${local.name}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# -----------------------------------------------------------------------------
# IAM database authentication. Services on EKS reach the database with
# short-lived auth tokens minted by their pod's IAM role (IRSA) - no database
# passwords in application configuration or OpenTofu state. This managed policy
# is what service teams attach to their roles: it grants rds-db:connect on both
# regional clusters, for any PostgreSQL role created for the service.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_db_connect" {
  statement {
    sid = "AllowRdsDbConnect"

    actions = ["rds-db:connect"]

    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*"
    ]
  }
}

resource "aws_iam_policy" "rds_db_connect" {
  name        = "${local.name}-rds-db-connect"
  description = "Allows IAM principals to mint RDS IAM-auth tokens for the ${var.name} (${var.environment}) database in both regions."
  policy      = data.aws_iam_policy_document.rds_db_connect.json
}
