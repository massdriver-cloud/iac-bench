# ---------------------------------------------------------------------------
# Pre-create the CloudWatch log groups Aurora exports to, so we control
# retention and encryption (RDS would otherwise create them unencrypted with
# infinite retention).
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "primary" {
  provider = aws.primary

  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.primary.arn
}

resource "aws_cloudwatch_log_group" "secondary" {
  provider = aws.secondary

  name              = local.log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = aws_kms_key.secondary.arn
}
