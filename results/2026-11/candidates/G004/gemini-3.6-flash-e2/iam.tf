data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "db_iam_auth_primary" {
  name        = "${var.service_name}-${var.environment}-db-iam-auth-primary"
  description = "IAM policy allowing database connection via IAM authentication for ${var.service_name} in primary region"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${var.primary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.primary.cluster_resource_id}/*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_iam_policy" "db_iam_auth_secondary" {
  provider    = aws.secondary
  name        = "${var.service_name}-${var.environment}-db-iam-auth-secondary"
  description = "IAM policy allowing database connection via IAM authentication for ${var.service_name} in secondary region"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["rds-db:connect"]
        Resource = "arn:aws:rds-db:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:dbuser:${aws_rds_cluster.secondary.cluster_resource_id}/*"
      }
    ]
  })

  tags = local.common_tags
}
