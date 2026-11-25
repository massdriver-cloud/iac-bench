# Enhanced Monitoring (OS-level metrics) requires this IAM role. IAM is global,
# so one role serves the cluster instances in both regions.
data "aws_iam_policy_document" "rds_monitoring_assume_role" {
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
  name               = "${local.prefix}-enhanced-monitoring"
  assume_role_policy = data.aws_iam_policy_document.rds_monitoring_assume_role.json
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# Aurora would auto-create these log groups on first export with unlimited
# retention; we create them up front to pin a retention policy.
resource "aws_cloudwatch_log_group" "primary" {
  name              = "/aws/rds/cluster/${local.primary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days
}
