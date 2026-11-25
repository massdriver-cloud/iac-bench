data "aws_iam_policy_document" "rds_enhanced_monitoring_assume" {
  statement {
    sid     = "AllowRDSEnhancedMonitoringAssume"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_enhanced_monitoring" {
  name               = "${local.name_prefix}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_enhanced_monitoring_assume.json

  tags = {
    Name = "${local.name_prefix}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_enhanced_monitoring" {
  role       = aws_iam_role.rds_enhanced_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

data "aws_iam_policy_document" "eks_db_connect" {
  statement {
    sid     = "AllowIAMDBConnectBothRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]

    resources = flatten([
      for db_user in local.iam_db_users : [
        "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${db_user}",
        "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${db_user}"
      ]
    ])
  }
}

resource "aws_iam_policy" "eks_db_connect" {
  name        = "${local.name_prefix}-eks-db-connect"
  description = "Grants EKS service IAM roles rds-db:connect access to ${local.name_prefix} Aurora PostgreSQL in both ${var.primary_region} and ${var.secondary_region}."
  policy      = data.aws_iam_policy_document.eks_db_connect.json

  tags = {
    Name = "${local.name_prefix}-eks-db-connect"
  }
}
