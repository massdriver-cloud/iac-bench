resource "aws_kms_key" "primary" {
  count                   = var.kms_key_arn_primary == null ? 1 : 0
  provider                = aws
  description             = "KMS key for ${local.name_prefix} primary Aurora cluster"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "primary" {
  count         = var.kms_key_arn_primary == null ? 1 : 0
  provider      = aws
  name          = "alias/${local.name_prefix}-primary"
  target_key_id = aws_kms_key.primary[0].key_id
}

resource "aws_kms_key" "secondary" {
  count                   = var.kms_key_arn_secondary == null ? 1 : 0
  provider                = aws.secondary
  description             = "KMS key for ${local.name_prefix} secondary Aurora cluster"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = local.common_tags
}

resource "aws_kms_alias" "secondary" {
  count         = var.kms_key_arn_secondary == null ? 1 : 0
  provider      = aws.secondary
  name          = "alias/${local.name_prefix}-secondary"
  target_key_id = aws_kms_key.secondary[0].key_id
}

locals {
  primary_kms_key_arn   = var.kms_key_arn_primary != null ? var.kms_key_arn_primary : aws_kms_key.primary[0].arn
  secondary_kms_key_arn = var.kms_key_arn_secondary != null ? var.kms_key_arn_secondary : aws_kms_key.secondary[0].arn
}
