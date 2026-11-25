# IAM Database Authentication policy for EKS workloads

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid    = "AuroraPostgreSqlIAMDatabaseConnect"
    effect = "Allow"
    actions = [
      "rds-db:connect"
    ]
    resources = [
      "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*",
      "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*"
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  name        = "${local.name_prefix}-db-connect"
  description = "Allows EKS IAM roles to authenticate to Aurora PostgreSQL clusters via IAM"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "app_db_connect" {
  for_each   = toset(var.app_iam_role_names)
  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}
