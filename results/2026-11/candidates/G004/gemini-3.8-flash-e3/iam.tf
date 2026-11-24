# Enhanced Monitoring Role
data "aws_iam_policy_document" "monitoring_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "rds_monitoring" {
  name_prefix        = "${var.name}-rds-mon-"
  assume_role_policy = data.aws_iam_policy_document.monitoring_assume_role.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_monitoring" {
  role       = aws_iam_role.rds_monitoring.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# IAM Database Authentication Policy for EKS Services
data "aws_iam_policy_document" "rds_connect" {
  statement {
    sid    = "AllowRDSConnect"
    effect = "Allow"
    actions = [
      "rds-db:connect"
    ]
    resources = flatten([
      for dbuser in var.iam_database_users : [
        "arn:aws:rds-db:${var.primary_region}:${local.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/${dbuser}",
        "arn:aws:rds-db:${var.secondary_region}:${local.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/${dbuser}"
      ]
    ])
  }
}

resource "aws_iam_policy" "rds_connect" {
  name_prefix = "${var.name}-rds-connect-"
  description = "Grants permissions to connect to ${var.name} Aurora PostgreSQL cluster via IAM database authentication"
  policy      = data.aws_iam_policy_document.rds_connect.json
  tags        = local.common_tags
}

resource "aws_iam_role_policy_attachment" "rds_connect" {
  for_each   = toset(var.service_role_names)
  role       = each.value
  policy_arn = aws_iam_policy.rds_connect.arn
}
