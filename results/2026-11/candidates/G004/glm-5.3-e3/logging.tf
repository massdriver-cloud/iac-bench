###############################################################################
# CloudWatch log groups for the postgres and audit logs RDS exports.
#
# RDS auto-creates these groups with infinite retention when log exports are
# enabled; the module pre-creates them instead so retention is pinned
# explicitly — a payment-data compliance requirement (bounded retention) and a
# cost control in one. The names must match RDS's convention exactly:
# /aws/rds/cluster/<cluster-identifier>/<log-type>.
###############################################################################

resource "aws_cloudwatch_log_group" "primary_postgresql" {
  provider          = aws.primary
  name              = "/aws/rds/cluster/${local.primary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${local.primary_cluster_identifier}/postgresql"
  }
}

resource "aws_cloudwatch_log_group" "primary_audit" {
  provider          = aws.primary
  name              = "/aws/rds/cluster/${local.primary_cluster_identifier}/audit"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${local.primary_cluster_identifier}/audit"
  }
}

resource "aws_cloudwatch_log_group" "secondary_postgresql" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.secondary_cluster_identifier}/postgresql"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${local.secondary_cluster_identifier}/postgresql"
  }
}

resource "aws_cloudwatch_log_group" "secondary_audit" {
  provider          = aws.secondary
  name              = "/aws/rds/cluster/${local.secondary_cluster_identifier}/audit"
  retention_in_days = var.log_retention_in_days

  tags = {
    Name = "${local.secondary_cluster_identifier}/audit"
  }
}
