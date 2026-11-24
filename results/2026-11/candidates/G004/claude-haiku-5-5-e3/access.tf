# Applications reach the database with IAM authentication (rds-db:connect)
# instead of a password. The same role works in both regions, so a service
# that fails over keeps the same credentials path.

data "aws_partition" "current" {
  provider = aws.primary
}

data "aws_caller_identity" "current" {
  provider = aws.primary
}

data "aws_iam_policy_document" "db_connect" {
  statement {
    sid     = "ConnectAsIamDbUser"
    effect  = "Allow"
    actions = ["rds-db:connect"]

    resources = [
      "arn:${data.aws_partition.current.partition}:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${var.iam_db_user}",
      "arn:${data.aws_partition.current.partition}:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${var.iam_db_user}",
    ]
  }
}

resource "aws_iam_policy" "db_connect" {
  provider = aws.primary

  name        = "${local.name}-db-connect"
  description = "rds-db:connect as ${var.iam_db_user} on ${local.name} clusters in ${var.primary_region} and ${var.secondary_region}"
  policy      = data.aws_iam_policy_document.db_connect.json
}

resource "aws_iam_role_policy_attachment" "app" {
  provider = aws.primary
  for_each = toset(var.app_iam_role_names)

  role       = each.value
  policy_arn = aws_iam_policy.db_connect.arn
}

# Optional stable writer name. It points at the cluster selected by
# writer_region. Failover is: promote the secondary, then set
# writer_region = "secondary" and apply. See README.
resource "aws_route53_record" "writer" {
  provider = aws.primary
  count    = var.dns == null ? 0 : 1

  zone_id = var.dns.zone_id
  name    = var.dns.record_name
  type    = "CNAME"
  ttl     = 30
  records = [local.writer_endpoint]
}
