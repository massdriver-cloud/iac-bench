# Applications authenticate with IAM (EKS pod IAM roles / IRSA), not static
# passwords. Attach this policy to the service's pod role, create the matching
# PostgreSQL user with `GRANT rds_iam TO <app_db_username>;`, and connect with
# a short-lived IAM auth token over TLS. The policy covers both regions so it
# keeps working after a regional failover.
#
# Note: rds-db ARNs use the cluster's immutable DbiResourceId, which survives
# renames and restores.

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "AllowIAMDatabaseAuth"
    actions = ["rds-db:connect"]
    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.app_db_username}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.app_db_username}",
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  provider = aws.primary

  name        = "${local.name}-db-connect"
  description = "IAM database authentication to ${local.name} Aurora clusters (both regions) as ${var.app_db_username}"
  policy      = data.aws_iam_policy_document.db_connect.json

  tags = {
    Name = "${local.name}-db-connect"
  }
}
