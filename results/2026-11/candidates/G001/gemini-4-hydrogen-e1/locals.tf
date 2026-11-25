locals {
  raw_prefix  = "${var.application}-${var.environment}-${var.purpose}"
  name_prefix = "${trim(substr(local.raw_prefix, 0, 36), "-")}-"

  use_case_profiles = {
    assets = {
      versioning               = true
      noncurrent_days          = 90
      expiration_days          = null
      intelligent_tiering_days = 30
      ia_days                  = null
    }
    uploads = {
      versioning               = true
      noncurrent_days          = 90
      expiration_days          = null
      intelligent_tiering_days = 30
      ia_days                  = null
    }
    media = {
      versioning               = true
      noncurrent_days          = 90
      expiration_days          = null
      intelligent_tiering_days = 30
      ia_days                  = null
    }
    generated = {
      versioning               = true
      noncurrent_days          = 30
      expiration_days          = null
      intelligent_tiering_days = null
      ia_days                  = null
    }
    logs = {
      versioning               = false
      noncurrent_days          = 30
      expiration_days          = 365
      intelligent_tiering_days = null
      ia_days                  = 30
    }
  }

  profile = local.use_case_profiles[var.use_case]

  effective_versioning_enabled = coalesce(var.versioning_enabled, local.profile.versioning)

  effective_noncurrent_expiration_days = (
    var.noncurrent_version_expiration_days == 0
    ? null
    : coalesce(var.noncurrent_version_expiration_days, local.profile.noncurrent_days)
  )

  effective_object_expiration_days = (
    var.object_expiration_days == 0
    ? null
    : (var.object_expiration_days != null ? var.object_expiration_days : local.profile.expiration_days)
  )

  raw_intelligent_tiering_days = (
    var.intelligent_tiering_days == -1
    ? null
    : (var.intelligent_tiering_days != null ? var.intelligent_tiering_days : local.profile.intelligent_tiering_days)
  )

  effective_intelligent_tiering_days = (
    local.raw_intelligent_tiering_days != null &&
    (local.effective_object_expiration_days == null || local.raw_intelligent_tiering_days < local.effective_object_expiration_days)
    ? local.raw_intelligent_tiering_days
    : null
  )

  effective_ia_days = (
    local.profile.ia_days != null &&
    local.effective_intelligent_tiering_days == null &&
    (local.effective_object_expiration_days == null || local.profile.ia_days < local.effective_object_expiration_days)
    ? local.profile.ia_days
    : null
  )

  effective_access_log_prefix = coalesce(var.access_log_prefix, "${var.application}/${var.environment}/${var.purpose}/")

  common_tags = merge(
    var.tags,
    {
      Application = var.application
      Environment = var.environment
      Purpose     = var.purpose
      UseCase     = var.use_case
      ManagedBy   = "opentofu"
    }
  )
}
