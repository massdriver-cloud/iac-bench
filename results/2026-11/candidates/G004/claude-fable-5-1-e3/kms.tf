# One customer-managed key per region. Aurora Global Database requires a key
# in each region, and a CMK (rather than the AWS-managed aws/rds key) gives us
# auditable key usage and the ability to control access to backups/snapshots.

resource "aws_kms_key" "primary" {
  description             = "Aurora PostgreSQL ${local.name} (primary, ${var.primary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "primary" {
  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL ${local.name} (secondary, ${var.secondary_region})"
  deletion_window_in_days = 30
  enable_key_rotation     = true
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/rds/${local.name}"
  target_key_id = aws_kms_key.secondary.key_id
}
