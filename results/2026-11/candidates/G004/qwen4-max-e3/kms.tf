# Customer-managed KMS keys, one per region (Aurora Global Database encrypts
# each regional cluster with a key in that region). Rotation is enabled and
# the deletion window is the maximum, to protect payment/customer data.

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Aurora PostgreSQL CMK for ${local.name} (primary, ${var.primary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Aurora PostgreSQL CMK for ${local.name} (DR, ${var.secondary_region})"
  enable_key_rotation     = true
  deletion_window_in_days = 30

  tags = {
    Name = "${local.name}-aurora"
  }
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.name}-aurora"
  target_key_id = aws_kms_key.secondary.key_id
}
