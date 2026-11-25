# Customer-managed KMS keys encrypt cluster storage, snapshots, Performance
# Insights data and the RDS-managed master secret. KMS keys are regional, so
# the global database needs one key per region (Aurora re-encrypts replicated
# storage with the secondary region's key).

resource "aws_kms_key" "primary" {
  provider                = aws.primary
  description             = "Aurora PostgreSQL ${local.base_name} (${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "primary" {
  provider      = aws.primary
  name          = "alias/${local.base_name}-aurora-${var.primary_region}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  description             = "Aurora PostgreSQL ${local.base_name} (${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  name          = "alias/${local.base_name}-aurora-${var.secondary_region}"
  target_key_id = aws_kms_key.secondary.key_id
}
