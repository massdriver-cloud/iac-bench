# OS-level enhanced monitoring (IAM is global; one role serves both regions).

data "aws_iam_policy_document" "enhanced_monitoring_assume" {
  statement {
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

# Pre-create the engine log groups so retention is enforced from day one
# (otherwise RDS creates them with "never expire").

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary

  name              = "/aws/rds/cluster/${local.primary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name}-postgresql"
  }
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = "/aws/rds/cluster/${local.secondary_cluster_id}/postgresql"
  retention_in_days = var.log_retention_days

  tags = {
    Name = "${local.name}-postgresql"
  }
}
