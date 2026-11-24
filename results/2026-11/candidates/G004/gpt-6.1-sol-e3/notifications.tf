# Notification bodies contain operational identifiers only, never SQL or credentials.
# RDS and CloudWatch must be able to publish to each encrypted regional topic.
data "aws_iam_policy_document" "notification_key" {
  statement {
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }
  statement {
    actions   = ["kms:Decrypt", "kms:GenerateDataKey*"]
    resources = ["*"]
    principals {
      type        = "Service"
      identifiers = ["cloudwatch.amazonaws.com", "rds.amazonaws.com", "sns.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "kms:EncryptionContext:aws:sns:topicArn"
      values = [
        "arn:${data.aws_partition.current.partition}:sns:${var.primary_region}:${data.aws_caller_identity.current.account_id}:${local.prefix}-database-alerts",
        "arn:${data.aws_partition.current.partition}:sns:${var.secondary_region}:${data.aws_caller_identity.current.account_id}:${local.prefix}-database-alerts"
      ]
    }
  }
}
resource "aws_kms_key" "notifications_primary" {
  description             = "${local.prefix} encrypted operational notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.notification_key.json
}
resource "aws_kms_key" "notifications_secondary" {
  provider                = aws.secondary
  description             = "${local.prefix} encrypted operational notifications"
  enable_key_rotation     = true
  deletion_window_in_days = 30
  policy                  = data.aws_iam_policy_document.notification_key.json
}
