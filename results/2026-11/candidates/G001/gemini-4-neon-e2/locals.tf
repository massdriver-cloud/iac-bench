data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
  partition  = data.aws_partition.current.partition

  # Deterministic, globally unique suffix derived from AWS account + region.
  account_region_suffix = substr(sha256("${local.account_id}:${local.region}"), 0, 8)
  name_prefix           = "${var.app_name}-${var.purpose}-${var.environment}"

  bucket_name = coalesce(
    var.bucket_name_override,
    "${local.name_prefix}-${local.account_region_suffix}"
  )

  # Ensure the companion access-log bucket name always stays within S3's 63-char limit.
  companion_log_bucket_name = (
    length("${local.bucket_name}-logs") <= 63
    ? "${local.bucket_name}-logs"
    : "${trim(substr(local.bucket_name, 0, 49), "-")}-${substr(sha256(local.bucket_name), 0, 8)}-logs"
  )

  # Workload profile defaults — chosen for safety, cost hygiene, and zero S3 guesswork.
  use_case_profiles = {
    assets = {
      versioning_enabled                    = true
      intelligent_tiering_enabled           = true
      object_expiration_days                = 0
      noncurrent_version_transition_ia_days = 30
      noncurrent_version_expiration_days    = 90
      logs_tiering_enabled                  = false
    }
    media = {
      versioning_enabled                    = true
      intelligent_tiering_enabled           = true
      object_expiration_days                = 0
      noncurrent_version_transition_ia_days = 0
      noncurrent_version_expiration_days    = 30
      logs_tiering_enabled                  = false
    }
    logs = {
      versioning_enabled                    = false
      intelligent_tiering_enabled           = false
      object_expiration_days                = 365
      noncurrent_version_transition_ia_days = 0
      noncurrent_version_expiration_days    = 30
      logs_tiering_enabled                  = true
    }
    ephemeral = {
      versioning_enabled                    = false
      intelligent_tiering_enabled           = false
      object_expiration_days                = 30
      noncurrent_version_transition_ia_days = 0
      noncurrent_version_expiration_days    = 7
      logs_tiering_enabled                  = false
    }
  }

  profile = local.use_case_profiles[var.use_case]

  # Resolved lifecycle & versioning settings (explicit variables override profile defaults).
  versioning_enabled                 = coalesce(var.versioning_enabled, local.profile.versioning_enabled)
  intelligent_tiering_enabled        = coalesce(var.intelligent_tiering_enabled, local.profile.intelligent_tiering_enabled)
  object_expiration_days             = coalesce(var.object_expiration_days, local.profile.object_expiration_days)
  noncurrent_version_expiration_days = coalesce(var.noncurrent_version_expiration_days, local.profile.noncurrent_version_expiration_days)

  # If the user lowered noncurrent expiration below the profile's default IA transition
  # without explicitly setting transition days, automatically skip the IA transition.
  noncurrent_version_transition_ia_days = (
    var.noncurrent_version_transition_ia_days != null
    ? var.noncurrent_version_transition_ia_days
    : (
      local.profile.noncurrent_version_transition_ia_days > 0 &&
      local.profile.noncurrent_version_transition_ia_days < local.noncurrent_version_expiration_days
      ? local.profile.noncurrent_version_transition_ia_days
      : 0
    )
  )

  logs_tiering_enabled = local.profile.logs_tiering_enabled && !local.intelligent_tiering_enabled
  logs_ia_days         = 30
  logs_glacier_ir_days = 90

  # Encryption settings.
  use_kms                = var.encryption_mode == "kms"
  create_kms_key         = local.use_kms && var.kms_key_arn == null
  kms_key_arn            = local.use_kms ? (var.kms_key_arn != null ? var.kms_key_arn : aws_kms_key.this[0].arn) : null
  kms_deletion_window    = coalesce(var.kms_deletion_window_in_days, var.environment == "prod" ? 30 : 7)
  expected_sse_algorithm = local.use_kms ? "aws:kms" : "AES256"

  # Server access logging settings.
  create_access_log_bucket = var.enable_access_logging && var.access_logging_target_bucket == null
  access_log_bucket_name   = var.enable_access_logging ? (var.access_logging_target_bucket != null ? var.access_logging_target_bucket : aws_s3_bucket.access_logs[0].id) : null

  # CORS safety checks.
  cors_enabled             = length(var.cors_allowed_origins) > 0
  cors_has_write_methods   = length(setintersection(toset(var.cors_allowed_methods), toset(["PUT", "POST", "DELETE"]))) > 0
  cors_has_wildcard_origin = contains(var.cors_allowed_origins, "*")

  # Standardized governance tags applied to all taggable resources.
  standard_tags = merge(
    {
      Application = var.app_name
      Environment = var.environment
      Purpose     = var.purpose
      UseCase     = var.use_case
      Owner       = var.owner
      ManagedBy   = "OpenTofu"
    },
    var.cost_center != null ? { CostCenter = var.cost_center } : {}
  )

  common_tags = merge(var.tags, local.standard_tags)
}
