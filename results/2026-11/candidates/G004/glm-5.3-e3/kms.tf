###############################################################################
# Customer-managed KMS key (primary region) for the cluster's storage and the
# RDS-managed master-user secret. Annual rotation is enabled; a 30-day
# deletion window guards against accidental deletion. Pass kms_key_arn to use
# an existing key (e.g. one owned by a central crypto team) instead.
###############################################################################

resource "aws_kms_key" "primary" {
  provider = aws.primary
  count    = var.kms_key_arn == null ? 1 : 0

  description             = "Aurora PostgreSQL storage and master-user secret key for ${local.name}"
  deletion_window_in_days = 30
  enable_key_rotation     = true

  tags = {
    Name = "${local.name}-aurora"
  }
}
