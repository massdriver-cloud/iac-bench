data "aws_iam_policy_document" "enhanced_monitoring_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["monitoring.rds.${data.aws_partition.primary.dns_suffix}"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "enhanced_monitoring" {
  name               = "${var.name}-aurora-enhanced-monitoring"
  description        = "Enhanced monitoring for ${var.name} Aurora in both Regions"
  assume_role_policy = data.aws_iam_policy_document.enhanced_monitoring_assume_role.json

  tags = {
    Name = "${var.name}-aurora-enhanced-monitoring"
  }
}

resource "aws_iam_role_policy_attachment" "enhanced_monitoring" {
  role       = aws_iam_role.enhanced_monitoring.name
  policy_arn = "arn:${data.aws_partition.primary.partition}:iam::aws:policy/service-role/AmazonRDSEnhancedMonitoringRole"
}

# rds-db:connect resource IDs are cluster-specific. Including both clusters in
# one policy lets the same EKS IAM role authenticate before and after recovery.
data "aws_iam_policy_document" "iam_database_connect" {
  count = local.create_iam_policy ? 1 : 0

  statement {
    sid     = "ConnectToBothAuroraRegions"
    effect  = "Allow"
    actions = ["rds-db:connect"]

    resources = flatten([
      for cluster in [
        {
          region      = var.primary_region
          resource_id = aws_rds_cluster.primary.cluster_resource_id
        },
        {
          region      = var.secondary_region
          resource_id = aws_rds_cluster.secondary.cluster_resource_id
        },
        ] : [
        for user in local.iam_database_users :
        "arn:${data.aws_partition.primary.partition}:rds-db:${cluster.region}:${data.aws_caller_identity.primary.account_id}:dbuser:${cluster.resource_id}/${user}"
      ]
    ])
  }
}

resource "aws_iam_policy" "iam_database_connect" {
  count = local.create_iam_policy ? 1 : 0

  name        = "${var.name}-aurora-iam-connect"
  description = "IAM authentication to ${var.name} Aurora PostgreSQL in either Region"
  policy      = data.aws_iam_policy_document.iam_database_connect[0].json

  tags = {
    Name = "${var.name}-aurora-iam-connect"
  }
}

resource "aws_iam_role_policy_attachment" "service_iam_database_connect" {
  for_each = local.create_iam_policy ? toset(var.service_iam_role_names) : toset([])

  role       = each.value
  policy_arn = aws_iam_policy.iam_database_connect[0].arn

  lifecycle {
    precondition {
      condition     = length(var.service_iam_role_names) == 0 || local.create_iam_policy
      error_message = "Set at least one iam_database_users entry when service_iam_role_names is configured."
    }
  }
}
