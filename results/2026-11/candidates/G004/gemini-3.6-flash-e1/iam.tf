data "aws_iam_policy_document" "db_connect_primary" {
  provider = aws
  statement {
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.primary.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*"
    ]
  }
}

resource "aws_iam_policy" "db_connect_primary" {
  provider    = aws
  name        = "${local.name_prefix}-primary-db-connect"
  description = "IAM policy to allow EKS workloads in primary region to connect to ${local.name_prefix} database"
  policy      = data.aws_iam_policy_document.db_connect_primary.json

  tags = local.common_tags
}

data "aws_iam_policy_document" "db_connect_secondary" {
  provider = aws.secondary
  statement {
    effect  = "Allow"
    actions = ["rds-db:connect"]
    resources = [
      "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.secondary.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*"
    ]
  }
}

resource "aws_iam_policy" "db_connect_secondary" {
  provider    = aws.secondary
  name        = "${local.name_prefix}-secondary-db-connect"
  description = "IAM policy to allow EKS workloads in secondary region to connect to ${local.name_prefix} database"
  policy      = data.aws_iam_policy_document.db_connect_secondary.json

  tags = local.common_tags
}
