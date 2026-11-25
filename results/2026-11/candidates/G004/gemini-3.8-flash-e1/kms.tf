resource "aws_kms_key" "primary" {
  count                   = var.primary_kms_key_arn == null ? 1 : 0
  description             = "KMS key for Aurora PostgreSQL ${var.name} in ${var.primary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.primary_tags
}

resource "aws_kms_alias" "primary" {
  count         = var.primary_kms_key_arn == null ? 1 : 0
  name          = "alias/${var.name}-aurora-${var.environment}"
  target_key_id = aws_kms_key.primary[0].key_id
}

resource "aws_kms_key" "secondary" {
  provider                = aws.secondary
  count                   = var.secondary_kms_key_arn == null ? 1 : 0
  description             = "KMS key for Aurora PostgreSQL ${var.name} in ${var.secondary_region}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.secondary_tags
}

resource "aws_kms_alias" "secondary" {
  provider      = aws.secondary
  count         = var.secondary_kms_key_arn == null ? 1 : 0
  name          = "alias/${var.name}-aurora-${var.environment}"
  target_key_id = aws_kms_key.secondary[0].key_id
}
