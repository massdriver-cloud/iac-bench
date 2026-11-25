###############################################################################
# IAM:
# 1. Enhanced monitoring role RDS assumes to publish OS metrics (IAM is
#    global, so one role serves both regions).
# 2. Per-region "rds-connect" policies services attach to their EKS IAM
#    roles (IRSA / Pod Identity) to use IAM database authentication instead
#    of long-lived database passwords.
###############################################################################

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  provider = aws.primary

  name               = "${local.name}-rds-monitoring"
  description        = "Enhanced OS monitoring for ${local.name} Aurora instances in both regions"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json

  tags = {
    Name = "${local.name}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  provider = aws.primary

  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "rds_connect_primary" {
  statement {
    sid       = "IAMDatabaseAuth"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*"]
  }
}

resource "aws_iam_policy" "rds_connect_primary" {
  provider = aws.primary

  name        = "${local.name}-rds-connect"
  description = "IAM database authentication to ${local.name} Aurora (attach to the service's EKS role in ${var.primary_region})"
  policy      = data.aws_iam_policy_document.rds_connect_primary.json

  tags = {
    Name = "${local.name}-rds-connect"
  }
}

data "aws_iam_policy_document" "rds_connect_secondary" {
  statement {
    sid       = "IAMDatabaseAuth"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = ["arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*"]
  }
}

resource "aws_iam_policy" "rds_connect_secondary" {
  provider = aws.secondary

  name        = "${local.name}-rds-connect"
  description = "IAM database authentication to ${local.name} Aurora (attach to the service's EKS role in ${var.secondary_region})"
  policy      = data.aws_iam_policy_document.rds_connect_secondary.json

  tags = {
    Name = "${local.name}-rds-connect"
  }
}
