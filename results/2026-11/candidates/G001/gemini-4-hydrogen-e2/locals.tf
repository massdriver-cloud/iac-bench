locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # Build a globally unique, deterministic, S3-compliant bucket name (<= 63 chars).
  raw_prefix = "${var.app_name}-${var.environment}-${var.purpose}"
  raw_name   = "${local.raw_prefix}-${local.account_id}-${local.region}"
  name_hash  = substr(sha256(local.raw_name), 0, 8)

  max_prefix_with_hash = 63 - 1 - length(local.name_hash) - 1 - length(local.account_id)
  trimmed_prefix       = trim(substr(local.raw_prefix, 0, local.max_prefix_with_hash), "-")

  bucket_name = (
    length(local.raw_name) <= 63
    ? local.raw_name
    : "${local.trimmed_prefix}-${local.name_hash}-${local.account_id}"
  )

  profile_defaults = {
    general = {
      versioning_enabled      = true
      expiration_days         = null
      noncurrent_days         = 30
      retain_newer_noncurrent = 3
    }
    uploads = {
      versioning_enabled      = true
      expiration_days         = null
      noncurrent_days         = 30
      retain_newer_noncurrent = 3
    }
    media = {
      versioning_enabled      = true
      expiration_days         = null
      noncurrent_days         = 30
      retain_newer_noncurrent = 2
    }
    generated = {
      versioning_enabled      = true
      expiration_days         = 90
      noncurrent_days         = 7
      retain_newer_noncurrent = null
    }
    logs = {
      versioning_enabled      = false
      expiration_days         = 365
      noncurrent_days         = 7
      retain_newer_noncurrent = null
    }
  }

  selected_profile = local.profile_defaults[var.asset_profile]

  versioning_enabled = (
    var.versioning_enabled != null
    ? var.versioning_enabled
    : local.selected_profile.versioning_enabled
  )

  effective_expiration_days = (
    var.expiration_days == 0
    ? null
    : (var.expiration_days != null ? var.expiration_days : local.selected_profile.expiration_days)
  )

  effective_noncurrent_days = coalesce(
    var.noncurrent_version_expiration_days,
    local.selected_profile.noncurrent_days
  )

  # Only transition objects >= 128 KB to Intelligent-Tiering if they won't expire sooner.
  effective_tiering_enabled = (
    var.intelligent_tiering_enabled &&
    (local.effective_expiration_days == null || local.effective_expiration_days > var.intelligent_tiering_transition_days)
  )

  common_tags = merge(
    var.tags,
    {
      App          = var.app_name
      Environment  = var.environment
      Purpose      = var.purpose
      AssetProfile = var.asset_profile
      ManagedBy    = "opentofu"
    }
  )
}
