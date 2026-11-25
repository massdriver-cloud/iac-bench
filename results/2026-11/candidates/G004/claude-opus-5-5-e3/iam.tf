# IAM database authentication for application roles (EKS IRSA / Pod Identity).
# Connect permission covers both regional clusters so services keep working
# after a cross-region failover without any IAM change.

data "aws_iam_policy_document" "connect" {
  statement {
    sid     = "AuroraIamConnect"
    actions = ["rds-db:connect"]
    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${local.iam_db_user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${local.iam_db_user}",
    ]
  }
}

resource "aws_iam_policy" "connect" {
  name        = "${local.name}-aurora-connect"
  description = "Allow IAM authentication to Aurora ${local.name} as ${local.iam_db_user}"
  policy      = data.aws_iam_policy_document.connect.json
}

resource "aws_iam_role_policy_attachment" "connect" {
  for_each = toset(var.app_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.connect.arn
}
