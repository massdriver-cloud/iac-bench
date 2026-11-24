data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region

  ##############################################################################
  # Deterministic, globally unique bucket naming (strictly <= 63 chars)
  ##############################################################################
  base_slug      = "${var.application}-${var.environment}-${var.purpose}"
  unique_suffix  = "${local.account_id}-${local.region}"
  max_slug_len   = 58 - length(local.unique_suffix) - 1 # Reserve 5 chars for "-logs" on companion log bucket
  truncated_slug = "${trimsuffix(substr(local.base_slug, 0, local.max_slug_len - 9), "-")}-${substr(sha256(local.base_slug), 0, 8)}"
  resolved_slug  = length(local.base_slug) <= local.max_slug_len ? local.base_slug : local.truncated_slug

  bucket_name = var.bucket_name != null ? var.bucket_name : "${local.resolved_slug}-${local.unique_suffix}"

  create_access_log_bucket = var.enable_access_logging && var.access_log_bucket_name == null
  companion_log_bucket_name = (
    length("${local.bucket_name}-logs") <= 63
    ? "${local.bucket_name}-logs"
    : "${trimsuffix(substr(local.bucket_name, 0, 49), "-")}-${substr(sha256(local.bucket_name), 0, 8)}-logs"
  )
  target_access_log_bucket = var.access_log_bucket_name != null ? var.access_log_bucket_name : (local.create_access_log_bucket ? aws_s3_bucket.access_logs[0].id : null)
  access_log_prefix        = var.access_log_prefix != null ? "${trimsuffix(var.access_log_prefix, "/")}/" : "${local.bucket_name}/"

  ##############################################################################
  # Encryption flags
  ##############################################################################
  use_kms        = var.encryption_type == "kms"
  create_kms_key = local.use_kms && var.kms_key_arn == null
  kms_key_arn    = local.use_kms ? (local.create_kms_key ? aws_kms_key.this[0].arn : var.kms_key_arn) : null

  ##############################################################################
  # Opinionated workload presets (all individually overridable via variables)
  ##############################################################################
  workload_profiles = {
    general = {
      intelligent_tiering            = true
      object_expiration_days         = null
      archive_after_days             = null
      noncurrent_transition_days     = 30
      noncurrent_expiration_days     = 90
      abort_incomplete_multipart_day = 7
    }
    user-uploads = {
      intelligent_tiering            = true
      object_expiration_days         = null
      archive_after_days             = null
      noncurrent_transition_days     = 30
      noncurrent_expiration_days     = 90
      abort_incomplete_multipart_day = 7
    }
    media = {
      intelligent_tiering            = true
      object_expiration_days         = null
      archive_after_days             = null
      noncurrent_transition_days     = null
      noncurrent_expiration_days     = 30
      abort_incomplete_multipart_day = 3
    }
    generated = {
      intelligent_tiering            = false
      object_expiration_days         = 30
      archive_after_days             = null
      noncurrent_transition_days     = null
      noncurrent_expiration_days     = 14
      abort_incomplete_multipart_day = 7
    }
    logs = {
      intelligent_tiering            = false
      object_expiration_days         = 365
      archive_after_days             = 30
      noncurrent_transition_days     = null
      noncurrent_expiration_days     = 30
      abort_incomplete_multipart_day = 7
    }
  }

  profile = local.workload_profiles[var.workload_type]

  effective_intelligent_tiering        = var.enable_intelligent_tiering != null ? var.enable_intelligent_tiering : local.profile.intelligent_tiering
  effective_object_expiration_days     = var.object_expiration_days != null ? var.object_expiration_days : local.profile.object_expiration_days
  effective_archive_after_days         = var.archive_after_days != null ? var.archive_after_days : local.profile.archive_after_days
  effective_noncurrent_expiration_days = var.noncurrent_version_expiration_days != null ? var.noncurrent_version_expiration_days : local.profile.noncurrent_expiration_days
  effective_noncurrent_transition_days = var.noncurrent_version_transition_days != null ? var.noncurrent_version_transition_days : local.profile.noncurrent_transition_days
  effective_abort_multipart_days       = var.abort_incomplete_multipart_upload_days != null ? var.abort_incomplete_multipart_upload_days : local.profile.abort_incomplete_multipart_day

  # Guard against AWS S3 API error where noncurrent transition >= noncurrent expiration.
  # Use STANDARD_IA when transition >= 30 days (avoids 90-day Glacier_IR early-deletion
  # charges on 90-day noncurrent retention); use GLACIER_IR when < 30 days.
  enable_noncurrent_transition = (
    var.enable_versioning &&
    local.effective_noncurrent_transition_days != null &&
    local.effective_noncurrent_transition_days < local.effective_noncurrent_expiration_days
  )
  effective_noncurrent_transition_storage_class = (
    local.effective_noncurrent_transition_days != null && local.effective_noncurrent_transition_days >= 30
    ? "STANDARD_IA"
    : "GLACIER_IR"
  )

  ##############################################################################
  # Standardized resource tags
  ##############################################################################
  common_tags = merge(
    var.tags,
    {
      Application  = var.application
      Environment  = var.environment
      Purpose      = var.purpose
      WorkloadType = var.workload_type
      ManagedBy    = "OpenTofu"
    },
    var.owner != null ? { Owner = var.owner } : {},
    var.cost_center != null ? { CostCenter = var.cost_center } : {}
  )
}
