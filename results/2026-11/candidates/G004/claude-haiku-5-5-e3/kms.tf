# One customer-managed key per region. Each regional cluster encrypts its own
# storage, backups, Performance Insights data and the master password secret
# with the key in its region. Keys are never replicated, so a regional key
# outage does not reach across regions.

resource "aws_kms_key" "primary" {
  provider = aws.primary

  description             = "Encryption for ${local.primary_cluster_id} (storage, backups, PI, master secret)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
}

resource "aws_kms_alias" "primary" {
  provider = aws.primary

  name          = "alias/${local.primary_cluster_id}"
  target_key_id = aws_kms_key.primary.key_id
}

resource "aws_kms_key" "secondary" {
  provider = aws.secondary

  description             = "Encryption for ${local.secondary_cluster_id} (storage, backups, PI)"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
}

resource "aws_kms_alias" "secondary" {
  provider = aws.secondary

  name          = "alias/${local.secondary_cluster_id}"
  target_key_id = aws_kms_key.secondary.key_id
}
