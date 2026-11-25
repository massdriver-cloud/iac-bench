###############################################################################
# Enhanced Monitoring runs an agent on every Aurora instance; it needs a role
# the monitoring service can assume. IAM is global, so one role serves the
# clusters in both regions.
###############################################################################

data "aws_iam_policy_document" "rds_monitoring_assume" {
  provider = aws.primary

  statement {
    sid     = "AllowRdsMonitoringServiceAssumeRole"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  provider = aws.primary

  name               = "${local.name}-rds-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume.json

  tags = {
    Name = "${local.name}-rds-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  provider   = aws.primary
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/AmazonRDSEnhancedMonitoringRole"
}
