data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.region
  partition  = data.aws_partition.current.partition

  # Globally unique, human-readable bucket naming by default.
  default_bucket_name = "${var.app_name}-${var.purpose}-${var.environment}-${local.account_id}-${local.region}"
  bucket_name         = coalesce(var.bucket_name_override, local.default_bucket_name)

  # Environment classification for guardrails.
  is_production = contains(["prod", "production"], var.environment)

  # Encryption settings.
  use_kms        = var.encryption_type == "kms"
  create_kms_key = local.use_kms && var.kms_key_arn == null
  kms_key_arn    = local.use_kms ? (local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn) : null
  sse_algorithm  = local.use_kms ? "aws:kms" : "AES256"

  # Workload profiles encapsulate S3 lifecycle and versioning best practices
  # so developers only pick a workload intent instead of tuning storage classes.
  workload_profiles = {
    assets = {
      versioning_enabled                     = true
      enable_intelligent_tiering             = true
      object_expiration_days                 = null
      noncurrent_version_expiration_days     = 90
      noncurrent_version_ia_transition_days  = 30
      abort_incomplete_multipart_upload_days = 7
      transitions                            = []
    }
    temporary = {
      versioning_enabled                     = false
      enable_intelligent_tiering             = false
      object_expiration_days                 = 30
      noncurrent_version_expiration_days     = 7
      noncurrent_version_ia_transition_days  = null
      abort_incomplete_multipart_upload_days = 3
      transitions                            = []
    }
    logs = {
      versioning_enabled                     = false
      enable_intelligent_tiering             = false
      object_expiration_days                 = 365
      noncurrent_version_expiration_days     = 30
      noncurrent_version_ia_transition_days  = null
      abort_incomplete_multipart_upload_days = 7
      transitions = [
        { days = 30, storage_class = "STANDARD_IA" },
        { days = 90, storage_class = "GLACIER_IR" },
        { days = 180, storage_class = "GLACIER" },
      ]
    }
    archive = {
      versioning_enabled                     = true
      enable_intelligent_tiering             = false
      object_expiration_days                 = null
      noncurrent_version_expiration_days     = 365
      noncurrent_version_ia_transition_days  = 30
      abort_incomplete_multipart_upload_days = 7
      transitions = [
        { days = 30, storage_class = "GLACIER_IR" },
        { days = 180, storage_class = "DEEP_ARCHIVE" },
      ]
    }
  }

  profile = local.workload_profiles[var.workload_profile]

  versioning_enabled                     = var.versioning_enabled != null ? var.versioning_enabled : local.profile.versioning_enabled
  object_expiration_days                 = var.object_expiration_days != null ? var.object_expiration_days : local.profile.object_expiration_days
  noncurrent_version_expiration_days     = var.noncurrent_version_expiration_days != null ? var.noncurrent_version_expiration_days : local.profile.noncurrent_version_expiration_days
  abort_incomplete_multipart_upload_days = var.abort_incomplete_multipart_upload_days != null ? var.abort_incomplete_multipart_upload_days : local.profile.abort_incomplete_multipart_upload_days

  # Filter profile transitions so a shortened object_expiration_days override never
  # produces an invalid lifecycle rule (transition days must be < expiration days).
  effective_transitions = [
    for t in local.profile.transitions : t
    if local.object_expiration_days == null || t.days < local.object_expiration_days
  ]

  # Intelligent-Tiering is skipped if objects expire quickly (< 30 days).
  enable_intelligent_tiering = (
    local.profile.enable_intelligent_tiering &&
    (local.object_expiration_days == null || local.object_expiration_days >= 30)
  )

  # Only transition noncurrent versions to STANDARD_IA if they live longer than 30 days.
  enable_noncurrent_ia_transition = (
    local.versioning_enabled &&
    local.profile.noncurrent_version_ia_transition_days != null &&
    (local.noncurrent_version_expiration_days == null || local.profile.noncurrent_version_ia_transition_days < local.noncurrent_version_expiration_days)
  )

  # Guardrail against wildcard CORS origins combined with write methods.
  cors_has_wildcard_with_writes = (
    contains(var.cors_allowed_origins, "*") &&
    length(setintersection(toset(var.cors_allowed_methods), toset(["PUT", "POST", "DELETE"]))) > 0
  )

  # Consistent governance and cost-allocation tags applied to all resources.
  standard_tags = merge(
    {
      Application        = var.app_name
      Environment        = var.environment
      Purpose            = var.purpose
      WorkloadProfile    = var.workload_profile
      DataClassification = var.data_classification
      ManagedBy          = "opentofu"
    },
    var.owner != null ? { Owner = var.owner } : {}
  )

  common_tags = merge(var.tags, local.standard_tags)
}
