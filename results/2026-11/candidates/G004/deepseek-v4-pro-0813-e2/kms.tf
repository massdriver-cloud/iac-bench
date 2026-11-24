#
# Customer-managed KMS keys, one in each region. Global Aurora databases are
# encrypted by default; using separate regional keys keeps the secondary cluster
# independent if a key in one region is unavailable.
#

resource "aws_kms_key" "primary" {
  provider = aws.primary
  count    = var.create_kms_key ? 1 : 0

  description             = "Aurora PostgreSQL storage encryption key for ${var.service_name} (${var.environment}) primary"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-primary-aurora"
      Region = var.primary_region
    }
  )
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary
  count    = var.create_kms_key ? 1 : 0

  description             = "Aurora PostgreSQL storage encryption key for ${var.service_name} (${var.environment}) secondary"
  deletion_window_in_days = var.kms_deletion_window_in_days
  enable_key_rotation     = true

  tags = merge(
    local.default_tags,
    {
      Name   = "${local.prefix}-secondary-aurora"
      Region = var.secondary_region
    }
  )
}