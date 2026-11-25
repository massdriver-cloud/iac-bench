data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region

  # Deterministic, globally unique, DNS-compliant bucket name (<= 63 chars, no dots).
  name_prefix = "${var.app_name}-${var.environment}-${var.purpose}"
  name_suffix = "${local.account_id}-${local.region}"
  raw_name    = "${local.name_prefix}-${local.name_suffix}"

  # If the combined name exceeds 63 chars, truncate the prefix and append a 6-char hash
  # to preserve uniqueness while staying within S3's 63-character limit.
  max_prefix_len = 63 - 1 - length(local.name_suffix) - 7
  truncated_name = "${trimsuffix(substr(local.name_prefix, 0, local.max_prefix_len), "-")}-${substr(md5(local.name_prefix), 0, 6)}-${local.name_suffix}"

  bucket_name = coalesce(
    var.bucket_name_override,
    length(local.raw_name) <= 63 ? local.raw_name : local.truncated_name
  )

  # Opinionated profile defaults tuned for each workload type.
  profile_defaults = {
    uploads = {
      versioning_enabled         = true
      noncurrent_days            = 90
      newer_noncurrent_versions  = 5
      multipart_abort_days       = 7
      tiering_strategy           = "INTELLIGENT_TIERING"
      ia_transition_days         = 30
      glacier_ir_transition_days = null
      default_expiration_days    = null
    }
    media = {
      versioning_enabled         = true
      noncurrent_days            = 30
      newer_noncurrent_versions  = 3
      multipart_abort_days       = 3
      tiering_strategy           = "INTELLIGENT_TIERING"
      ia_transition_days         = 30
      glacier_ir_transition_days = null
      default_expiration_days    = null
    }
    generated = {
      versioning_enabled         = true
      noncurrent_days            = 14
      newer_noncurrent_versions  = 2
      multipart_abort_days       = 7
      tiering_strategy           = "STANDARD_IA"
      ia_transition_days         = 30
      glacier_ir_transition_days = null
      default_expiration_days    = null
    }
    logs = {
      versioning_enabled         = false
      noncurrent_days            = 7
      newer_noncurrent_versions  = 1
      multipart_abort_days       = 7
      tiering_strategy           = "STANDARD_IA"
      ia_transition_days         = 30
      glacier_ir_transition_days = 90
      default_expiration_days    = 365
    }
  }

  profile = local.profile_defaults[var.usage_profile]

  effective_versioning_enabled = var.versioning_enabled != null ? var.versioning_enabled : local.profile.versioning_enabled
  effective_noncurrent_days    = var.noncurrent_version_retention_days != null ? var.noncurrent_version_retention_days : local.profile.noncurrent_days
  effective_expiration_days = (
    var.expiration_days == 0 ? null : (
      var.expiration_days != null ? var.expiration_days : local.profile.default_expiration_days
    )
  )

  # Minimum object size (128 KiB) before transitioning to IA or Intelligent-Tiering
  # to avoid S3 minimum-billable-size penalties and monitoring fees on small objects.
  min_tiering_object_bytes = 131072

  standard_tags = {
    Application  = var.app_name
    Environment  = var.environment
    Purpose      = var.purpose
    UsageProfile = var.usage_profile
    ManagedBy    = "opentofu"
  }

  merged_tags = merge(local.standard_tags, var.tags)
}
