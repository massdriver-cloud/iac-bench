# ---------------------------------------------------------------------------
# Enhanced monitoring role (IAM is global, so one role serves both regions)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRdsEnhancedMonitoringToAssume"
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
  name               = "${local.name}-rds-enhanced-monitoring"
  description        = "Lets Amazon RDS publish enhanced monitoring metrics for the ${local.name} Aurora clusters."
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json
}

data "aws_iam_policy" "rds_enhanced_monitoring" {
  count = var.monitoring_interval > 0 ? 1 : 0
  arn   = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  count      = var.monitoring_interval > 0 ? 1 : 0
  role       = aws_iam_role.rds_enhanced_monitoring[0].name
  policy_arn = data.aws_iam_policy.rds_enhanced_monitoring[0].arn
}

# ---------------------------------------------------------------------------
# IAM policy for services on EKS (IAM database authentication)
#
# With iam_db_users set, the module publishes one managed policy that grants
# rds-db:connect for those database users on BOTH regional clusters. Attach it
# to the EKS service account roles (IRSA) of the service; the users must also
# exist in the database and be granted the rds_iam role.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_db_connect" {
  count = length(var.iam_db_users) > 0 ? 1 : 0

  statement {
    sid     = "AllowIAMDatabaseAuthentication"
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = concat(
      [for user in var.iam_db_users : "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${user}"],
      [for user in var.iam_db_users : "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${user}"],
    )
  }
}

resource "aws_iam_policy" "rds_db_connect" {
  count  = length(var.iam_db_users) > 0 ? 1 : 0
  name   = "${local.name}-rds-db-connect"
  policy = data.aws_iam_policy_document.rds_db_connect[0].json
}
