# ---------------------------------------------------------------------------
# Enhanced Monitoring role
#
# IAM is global, so one role serves cluster instances in both regions.
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "rds_monitoring_trust" {
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
  name               = "${local.stack}-rds-monitoring"
  description        = "Allows Enhanced Monitoring for the ${var.name} (${var.environment}) Aurora clusters"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_trust.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}
