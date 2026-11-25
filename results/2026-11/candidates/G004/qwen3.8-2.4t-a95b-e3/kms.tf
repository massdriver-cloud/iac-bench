# ---------------------------------------------------------------------------
# Encryption keys
#
# Customer and payment data is encrypted at rest with a customer-managed KMS
# key per region (KMS keys do not cross regions), with automatic annual
# rotation. Performance Insights and the managed master-password secret also
# use these keys where applicable.
# ---------------------------------------------------------------------------

resource "aws_kms_key" "primary" {
  provider = aws

  description             = "Aurora PostgreSQL encryption key for ${var.name} (${var.environment}) in ${var.primary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${local.stack}-aurora"
  }
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL encryption key for ${var.name} (${var.environment}) in ${var.secondary_region}"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${local.stack}-aurora"
  }
}

resource "aws_kms_alias" "primary" {
  provider = aws

  name          = "alias/${local.stack}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.stack}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
