# ---------------------------------------------------------------------------
# IAM supporting pieces
# ---------------------------------------------------------------------------

# Enhanced Monitoring role used by every Aurora instance (both regions; IAM
# is global so one role is enough).
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
  name               = "${local.name_env}-rds-monitoring"
  description        = "Enhanced Monitoring role for the ${local.name_env} Aurora clusters."
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume.json
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM database authentication policy for the EKS service roles: allows
# connecting to the master user on both clusters (primary and DR region).
# Attach this policy to the IAM roles the service pods assume.
data "aws_iam_policy_document" "iam_db_auth" {
  statement {
    sid       = "AllowRdsDbConnect"
    effect    = "Allow"
    actions   = ["rds-db:connect"]
    resources = [local.primary_dbuser_arn, local.secondary_dbuser_arn]
  }
}

resource "aws_iam_policy" "iam_db_auth" {
  name        = "${local.name_env}-aurora-iam-auth"
  description = "Grants rds-db:connect to the ${local.name_env} Aurora PostgreSQL clusters as ${var.master_username} (attach to the service's EKS IAM roles)."
  policy      = data.aws_iam_policy_document.iam_db_auth.json
}
