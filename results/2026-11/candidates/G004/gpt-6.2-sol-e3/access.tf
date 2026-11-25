data "aws_iam_policy_document" "runtime" {
  statement {
    sid     = "ConnectAsRuntimeRole"
    actions = ["rds-db:connect"]
    resources = [
      "arn:${local.partition}:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${local.app_user}",
      "arn:${local.partition}:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${local.app_user}",
    ]
  }
}

resource "aws_iam_policy" "runtime" {
  name        = "${local.name}-aurora-runtime"
  description = "Allows this service's workload roles to log in as ${local.app_user} in either region."
  policy      = data.aws_iam_policy_document.runtime.json
}

resource "aws_iam_role_policy_attachment" "runtime" {
  for_each   = var.app_iam_role_names
  role       = each.value
  policy_arn = aws_iam_policy.runtime.arn
}
